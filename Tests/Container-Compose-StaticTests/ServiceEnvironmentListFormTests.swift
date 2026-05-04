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
@testable import Yams
@testable import ContainerComposeCore

/// Coverage for both shapes of `services.<svc>.environment` allowed by the
/// Compose spec (map form and list form). Issue #2 reported the list form
/// failing to parse.
@Suite("Service Environment List Form")
struct ServiceEnvironmentListFormTests {

    // MARK: - End-to-end YAML decoding

    @Test("Map form decodes (regression — already-working path)")
    func mapFormDecodes() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            environment:
              FOO: bar
              COUNT: "3"
        """
        let compose = try YAMLDecoder().decode(DockerCompose.self, from: yaml)
        let env = try #require(compose.services["app"]??.environment)
        #expect(env["FOO"] == "bar")
        #expect(env["COUNT"] == "3")
    }

    @Test("List form decodes (the issue #2 case)")
    func listFormDecodes() throws {
        let yaml = """
        services:
          registry:
            image: registry:2
            environment:
              - REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/data
              - REGISTRY_STORAGE_DELETE_ENABLED=true
        """
        let compose = try YAMLDecoder().decode(DockerCompose.self, from: yaml)
        let env = try #require(compose.services["registry"]??.environment)
        #expect(env["REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY"] == "/data")
        #expect(env["REGISTRY_STORAGE_DELETE_ENABLED"] == "true")
    }

    @Test("Mixed forms across services in the same file")
    func mixedFormsAcrossServices() throws {
        let yaml = """
        services:
          a:
            image: alpine:latest
            environment:
              FOO: bar
          b:
            image: alpine:latest
            environment:
              - FOO=bar
        """
        let compose = try YAMLDecoder().decode(DockerCompose.self, from: yaml)
        #expect(compose.services["a"]??.environment?["FOO"] == "bar")
        #expect(compose.services["b"]??.environment?["FOO"] == "bar")
    }

    @Test("List form with no environment key decodes as nil")
    func listFormAbsentDecodesAsNil() throws {
        let yaml = """
        services:
          a:
            image: alpine:latest
        """
        let compose = try YAMLDecoder().decode(DockerCompose.self, from: yaml)
        #expect(compose.services["a"]??.environment == nil)
    }

    // MARK: - Pure helper

    @Test("Helper: KEY=value splits at first =")
    func helperSimpleKeyValue() {
        let result = Service.parseEnvironmentList(["FOO=bar", "COUNT=3"])
        #expect(result == ["FOO": "bar", "COUNT": "3"])
    }

    @Test("Helper: only the first = splits, rest stays in value")
    func helperFirstEqualsOnly() {
        let result = Service.parseEnvironmentList([
            "DSN=postgres://user:pw@host:5432/db?sslmode=require"
        ])
        #expect(result["DSN"] == "postgres://user:pw@host:5432/db?sslmode=require")
    }

    @Test("Helper: empty value after = decodes as empty string")
    func helperEmptyValue() {
        let result = Service.parseEnvironmentList(["FOO="])
        #expect(result["FOO"] == "")
    }

    @Test("Helper: bare key inherits from process env when set")
    func helperBareKeyInheritsFromHost() {
        // HOME is reliably set on macOS / CI. We don't assert the exact value,
        // only that the helper passed through the actual process env.
        let host = ProcessInfo.processInfo.environment["HOME"]
        let result = Service.parseEnvironmentList(["HOME"])
        #expect(result["HOME"] == host)
        #expect(result["HOME"]?.isEmpty == false, "HOME should be a non-empty path on this host")
    }

    @Test("Helper: bare key with no host env value decodes as empty string")
    func helperBareKeyMissingHostValue() {
        // A name unlikely to ever exist in the process env — uniquify per run
        // so concurrent runs/repeats can't pollute it.
        let name = "CC_TEST_UNSET_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
        #expect(ProcessInfo.processInfo.environment[name] == nil,
                "precondition: \(name) must not be set")
        let result = Service.parseEnvironmentList([name])
        #expect(result[name] == "")
    }

    @Test("Helper: empty list returns empty dict")
    func helperEmptyList() {
        let result = Service.parseEnvironmentList([])
        #expect(result == [:])
    }

    @Test("Helper: duplicate keys — last wins (matches docker compose precedence)")
    func helperDuplicateKeys() {
        let result = Service.parseEnvironmentList(["FOO=first", "FOO=second"])
        #expect(result["FOO"] == "second")
    }
}
