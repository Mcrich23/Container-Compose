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

import Foundation
import Testing
import Yams
@testable import ContainerComposeCore

struct ServiceEnvironmentAssemblyTests {
    @Test func filesAndExplicitValuesUseSeparateInterpolationSources() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "ORDER=first\nOVERRIDE=file\nONLY_FILE=kept".write(to: directory.appendingPathComponent("first.env"), atomically: true, encoding: .utf8)
        try "ORDER=second".write(to: directory.appendingPathComponent("second.env"), atomically: true, encoding: .utf8)
        let service = try YAMLDecoder().decode(Service.self, from: """
        image: alpine
        env_file: [first.env, second.env]
        environment:
          OVERRIDE: ${CC_ASSEMBLY_VALUE:-fallback}
          CC_ASSEMBLY_SELF: ${CC_ASSEMBLY_SELF:-self-default}
          EMPTY: ""
        """)
        let result = assembleServiceEnvironment(service: service, composeDirectory: directory.path,
            interpolationEnvironment: ["UNRELATED": "private", "ORDER": "dotenv", "CC_ASSEMBLY_VALUE": "external"])
        #expect(result == ["ORDER": "second", "OVERRIDE": "external", "ONLY_FILE": "kept", "EMPTY": "", "CC_ASSEMBLY_SELF": "self-default"])
        let defaulted = assembleServiceEnvironment(service: service, composeDirectory: directory.path, interpolationEnvironment: [:])
        #expect(defaulted["OVERRIDE"] == "fallback")
    }
}
