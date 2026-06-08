//===----------------------------------------------------------------------===//
// Copyright © 2025 Morris Richman and the Container-Compose project authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import Testing
import Foundation
import Yams
@testable import ContainerComposeCore

@Suite("Compose multi-file merge")
struct ComposeMergeYAMLTests {

    /// Parses a YAML document into a `Node`, failing the test if it can't.
    private func node(_ yaml: String) throws -> Node {
        try #require(try Yams.compose(yaml: yaml))
    }

    /// Convenience for reading a scalar value out of a mapping node by key.
    private func scalar(_ node: Node, _ key: String) -> String? {
        guard case .mapping(let map) = node, let value = map[key] else { return nil }
        return value.scalar?.string
    }

    @Test("Two mappings merge key-by-key, keys unique to each side survive")
    func mergesDisjointKeys() throws {
        let base = try node("a: 1\nb: 2\n")
        let override = try node("c: 3\nd: 4\n")

        let merged = ComposeProjectOptions.mergeYAML(base, override)

        #expect(scalar(merged, "a") == "1")
        #expect(scalar(merged, "b") == "2")
        #expect(scalar(merged, "c") == "3")
        #expect(scalar(merged, "d") == "4")
    }

    @Test("Overlapping scalar key: override wins")
    func overlappingScalarOverrideWins() throws {
        let base = try node("image: nginx:1.0\nname: web\n")
        let override = try node("image: nginx:2.0\n")

        let merged = ComposeProjectOptions.mergeYAML(base, override)

        #expect(scalar(merged, "image") == "nginx:2.0")
        // Untouched key from the base is preserved.
        #expect(scalar(merged, "name") == "web")
    }

    @Test("Overlapping map key is recursively merged")
    func overlappingMapRecursivelyMerged() throws {
        let base = try node("""
            service:
              environment:
                A: base-a
                B: base-b
            """)
        let override = try node("""
            service:
              environment:
                B: override-b
                C: override-c
            """)

        let merged = ComposeProjectOptions.mergeYAML(base, override)

        guard case .mapping(let root) = merged,
              let service = root["service"],
              case .mapping(let serviceMap) = service,
              let environment = serviceMap["environment"]
        else {
            Issue.record("expected service.environment mapping in merged result")
            return
        }

        #expect(scalar(environment, "A") == "base-a")       // unique to base survives
        #expect(scalar(environment, "B") == "override-b")   // overlap: override wins
        #expect(scalar(environment, "C") == "override-c")   // unique to override added
    }

    @Test("Sequence values are replaced by override, not concatenated")
    func sequencesAreReplaced() throws {
        let base = try node("ports:\n  - \"80\"\n")
        let override = try node("ports:\n  - \"443\"\n")

        let merged = ComposeProjectOptions.mergeYAML(base, override)

        guard case .mapping(let root) = merged,
              let ports = root["ports"],
              case .sequence(let seq) = ports
        else {
            Issue.record("expected ports sequence in merged result")
            return
        }

        #expect(seq.count == 1)
        #expect(seq.first?.scalar?.string == "443")
    }

    @Test("Non-mapping base with mapping override: override wins")
    func scalarBaseMappingOverrideOverrideWins() throws {
        let base = try node("x: \"just a string\"\n")
        let override = try node("""
            x:
              nested: value
            """)

        let merged = ComposeProjectOptions.mergeYAML(base, override)

        guard case .mapping(let root) = merged, let x = root["x"] else {
            Issue.record("expected key x in merged result")
            return
        }
        #expect(scalar(x, "nested") == "value")
    }

    @Test("Mapping base with non-mapping override: override wins")
    func mappingBaseScalarOverrideOverrideWins() throws {
        let base = try node("""
            x:
              nested: value
            """)
        let override = try node("x: \"just a string\"\n")

        let merged = ComposeProjectOptions.mergeYAML(base, override)

        #expect(scalar(merged, "x") == "just a string")
    }

    @Test("Top-level non-mapping override replaces base entirely")
    func topLevelNonMappingReplaces() throws {
        let base = try node("a: 1\n")
        let override = try node("- one\n- two\n")

        let merged = ComposeProjectOptions.mergeYAML(base, override)

        guard case .sequence(let seq) = merged else {
            Issue.record("expected sequence override to replace mapping base")
            return
        }
        #expect(seq.count == 2)
    }
}

@Suite("Project name precedence")
struct ProjectNameTests {

    /// A small valid compose document carrying an explicit `name:`.
    private func composeWithName() throws -> DockerCompose {
        try YAMLDecoder().decode(
            DockerCompose.self,
            from: "name: foo\nservices:\n  web:\n    image: x\n"
        )
    }

    /// A valid compose document with no top-level `name:`.
    private func composeWithoutName() throws -> DockerCompose {
        try YAMLDecoder().decode(
            DockerCompose.self,
            from: "services:\n  web:\n    image: x\n"
        )
    }

    @Test("--project-name override wins over compose name:")
    func overrideWinsOverComposeName() throws {
        let options = try ComposeProjectOptions.parse(["-p", "MYPROJ"])
        let compose = try composeWithName()

        #expect(options.projectName(for: compose) == "MYPROJ")
    }

    @Test("compose name: is used when no --project-name is given")
    func composeNameUsedWithoutOverride() throws {
        let options = try ComposeProjectOptions.parse([])
        let compose = try composeWithName()

        #expect(options.projectName(for: compose) == "foo")
    }

    @Test("falls back to sanitized directory name with neither override nor compose name:")
    func fallsBackToDirectoryName() throws {
        let cwd = "/tmp/Some.Project"
        let options = try ComposeProjectOptions.parse(["--cwd", cwd])
        let compose = try composeWithoutName()

        #expect(options.projectName(for: compose) == deriveProjectName(cwd: cwd))
    }
}

@Suite("Multi-file loadCompose merge")
struct LoadComposeMergeTests {

    @Test("Two -f files are deep-merged, later file overrides the earlier", .tempDir)
    func mergesTwoFiles() throws {
        let tmp = TempDirTrait.current

        let base = """
            services:
              web:
                image: nginx:1.0
                environment:
                  A: base-a
                  B: base-b
            """
        let override = """
            services:
              web:
                image: nginx:2.0
                environment:
                  B: override-b
                  C: override-c
            """

        let baseURL = tmp.appending(path: "compose.yaml")
        let overrideURL = tmp.appending(path: "compose.override.yaml")
        try base.write(to: baseURL, atomically: true, encoding: .utf8)
        try override.write(to: overrideURL, atomically: true, encoding: .utf8)

        let options = try ComposeProjectOptions.parse([
            "--cwd", tmp.path,
            "-f", baseURL.path,
            "-f", overrideURL.path,
        ])

        let compose = try options.loadCompose()
        let web = try #require(compose.services["web"] ?? nil)

        // Scalar override wins.
        #expect(web.image == "nginx:2.0")

        // Environment maps are deep-merged.
        let env = try #require(web.environment)
        #expect(env["A"] == "base-a")
        #expect(env["B"] == "override-b")
        #expect(env["C"] == "override-c")
    }
}
