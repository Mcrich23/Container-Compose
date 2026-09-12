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
@testable import ContainerComposeCore

@Suite("Compose pull Tests")
struct ComposePullTests {

    @Test("pull accepts service arguments alongside the project option group")
    func pullParsesArguments() throws {
        let cmd = try ComposePull.parse(["web", "db"])
        #expect(cmd.services == ["web", "db"])
    }

    @Test("pull accepts the shared -f/--cwd project options")
    func pullParsesProjectOptions() throws {
        let cmd = try ComposePull.parse(["-f", "my-compose.yaml", "--cwd", "/tmp"])
        #expect(cmd.project.composeFileOptions.composeFilename == "my-compose.yaml")
        #expect(cmd.project.cwd == "/tmp")
    }
}
