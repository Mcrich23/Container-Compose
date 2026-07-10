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

@Suite("Compose Project Resolution Tests")
struct ComposeProjectTests {

    private func decodeCompose(_ yaml: String) throws -> DockerCompose {
        try YAMLDecoder().decode(DockerCompose.self, from: yaml)
    }

    // MARK: - projectName(for:)

    @Test("Project name uses compose name: when present")
    func projectNameFromComposeName() throws {
        let options = try ComposeProjectOptions.parse(["--cwd", "/Users/user/Projects/SomeDir"])
        let compose = try decodeCompose(
            """
            name: my-named-project
            services:
              web:
                image: nginx
            """)
        #expect(options.projectName(for: compose) == "my-named-project")
    }

    @Test("Project name falls back to derived cwd name when name: absent")
    func projectNameDerivedFromCwd() throws {
        let options = try ComposeProjectOptions.parse(["--cwd", "/Users/user/Projects/My.Project"])
        let compose = try decodeCompose(
            """
            services:
              web:
                image: nginx
            """)
        #expect(options.projectName(for: compose) == deriveProjectName(cwd: "/Users/user/Projects/My.Project"))
        #expect(options.projectName(for: compose) == "My_Project")
    }

    // MARK: - composePath

    @Test("composePath honors explicit --file over discovery", .tempDir)
    func composePathExplicitFile() throws {
        let tmp = TempDirTrait.current
        // Create a discoverable default file too, to prove --file wins.
        let defaultFile = tmp.appending(path: "compose.yml")
        FileManager.default.createFile(atPath: defaultFile.path, contents: nil)

        let explicit = tmp.appending(path: "custom.yaml")
        FileManager.default.createFile(atPath: explicit.path, contents: nil)

        let options = try ComposeProjectOptions.parse(["--cwd", tmp.path, "-f", explicit.path])
        #expect(options.composePath == explicit.path)
    }

    @Test("composePath discovers the first supported filename in cwd", .tempDir)
    func composePathDiscoveryOrder() throws {
        let tmp = TempDirTrait.current
        // Create a lower-priority file first, then the top-priority one.
        let yamlFile = tmp.appending(path: "compose.yaml")
        let ymlFile = tmp.appending(path: "compose.yml")
        FileManager.default.createFile(atPath: yamlFile.path, contents: nil)
        FileManager.default.createFile(atPath: ymlFile.path, contents: nil)

        let options = try ComposeProjectOptions.parse(["--cwd", tmp.path])
        // compose.yml has higher priority than compose.yaml.
        #expect(options.composePath == ymlFile.path)
    }

    @Test("composePath discovers docker-compose.yml when higher-priority names are absent", .tempDir)
    func composePathDiscoversDockerCompose() throws {
        let tmp = TempDirTrait.current
        let dockerCompose = tmp.appending(path: "docker-compose.yml")
        FileManager.default.createFile(atPath: dockerCompose.path, contents: nil)

        let options = try ComposeProjectOptions.parse(["--cwd", tmp.path])
        #expect(options.composePath == dockerCompose.path)
    }

    @Test("composePath returns default compose.yml path when none exist", .tempDir)
    func composePathDefaultWhenNoneExist() throws {
        let tmp = TempDirTrait.current
        let options = try ComposeProjectOptions.parse(["--cwd", tmp.path])
        let expected = tmp.appending(path: "compose.yml").path
        #expect(options.composePath == expected)
        #expect(!FileManager.default.fileExists(atPath: expected))
    }

    // MARK: - orderedServices(of:filteringBy:)

    @Test("orderedServices returns dependencies before dependents")
    func orderedServicesTopologicalOrder() throws {
        let options = try ComposeProjectOptions.parse(["--cwd", "/tmp"])
        let compose = try decodeCompose(
            """
            services:
              web:
                image: nginx
                depends_on:
                  - app
              app:
                image: myapp
                depends_on:
                  - db
              db:
                image: postgres
            """)

        let ordered = try options.orderedServices(of: compose)
        let names = ordered.map(\.serviceName)
        #expect(names.count == 3)

        let dbIndex = try #require(names.firstIndex(of: "db"))
        let appIndex = try #require(names.firstIndex(of: "app"))
        let webIndex = try #require(names.firstIndex(of: "web"))
        #expect(dbIndex < appIndex)
        #expect(appIndex < webIndex)
    }

    @Test("orderedServices filters to the requested service names")
    func orderedServicesFiltering() throws {
        let options = try ComposeProjectOptions.parse(["--cwd", "/tmp"])
        let compose = try decodeCompose(
            """
            services:
              web:
                image: nginx
              app:
                image: myapp
              db:
                image: postgres
            """)

        let ordered = try options.orderedServices(of: compose, filteringBy: ["app"])
        #expect(ordered.map(\.serviceName) == ["app"])
    }
}
