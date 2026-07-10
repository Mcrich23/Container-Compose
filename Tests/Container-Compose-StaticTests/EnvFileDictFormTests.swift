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

/// Tests for the Compose 2.x extended `env_file` dict form:
///   env_file:
///     - path: ./config.env
///       required: false
///
/// The dict form may appear alone, alongside plain string entries in the same
/// array, or as the sole `env_file` value. All three must decode correctly.
@Suite("env_file dict-form parsing")
struct EnvFileDictFormTests {

    private func decodeService(_ serviceYaml: String) throws -> Service {
        let yaml = """
        services:
          svc:
        \(serviceYaml.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }.joined(separator: "\n"))
        """
        let compose = try YAMLDecoder().decode(DockerCompose.self, from: yaml)
        guard let service = compose.services["svc"].flatMap({ $0 }) else {
            Issue.record("service 'svc' missing or nil")
            throw TestError.missingService
        }
        return service
    }

    enum TestError: Error { case missingService }

    // MARK: - Regression: existing string forms still parse

    @Test("plain string env_file still parses")
    func plainString() throws {
        let svc = try decodeService("""
          image: alpine
          env_file: config/app.env
        """)
        #expect(svc.env_file == ["config/app.env"])
    }

    @Test("array of plain strings env_file still parses")
    func arrayOfStrings() throws {
        let svc = try decodeService("""
          image: alpine
          env_file:
            - config/app.env
            - config/secrets.env
        """)
        #expect(svc.env_file == ["config/app.env", "config/secrets.env"])
    }

    // MARK: - New: dict form

    @Test("single dict entry extracts path")
    func singleDictEntry() throws {
        let svc = try decodeService("""
          image: alpine
          env_file:
            - path: config/generated.env
              required: false
        """)
        #expect(svc.env_file == ["config/generated.env"])
    }

    @Test("dict entry with required: true extracts path")
    func dictEntryRequired() throws {
        let svc = try decodeService("""
          image: alpine
          env_file:
            - path: config/app.env
              required: true
        """)
        #expect(svc.env_file == ["config/app.env"])
    }

    @Test("dict entry without required field extracts path")
    func dictEntryNoRequired() throws {
        let svc = try decodeService("""
          image: alpine
          env_file:
            - path: config/app.env
        """)
        #expect(svc.env_file == ["config/app.env"])
    }

    @Test("multiple dict entries extract all paths in order")
    func multipleDictEntries() throws {
        let svc = try decodeService("""
          image: alpine
          env_file:
            - path: config/base.env
              required: true
            - path: config/optional.env
              required: false
        """)
        #expect(svc.env_file == ["config/base.env", "config/optional.env"])
    }

    @Test("mixed array of strings and dict entries extracts all paths")
    func mixedArray() throws {
        let svc = try decodeService("""
          image: alpine
          env_file:
            - config/base.env
            - path: config/generated.env
              required: false
        """)
        #expect(svc.env_file == ["config/base.env", "config/generated.env"])
    }
}
