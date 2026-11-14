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

@Suite("Compose stop/start Tests")
struct ComposeStopStartTests {

    @Test("stop parses service arguments and the shared project options")
    func stopParsesArguments() throws {
        let cmd = try ComposeStop.parse(["-f", "my-compose.yaml", "web", "db"])
        #expect(cmd.services == ["web", "db"])
        #expect(cmd.project.composeFileOptions.composeFilename == "my-compose.yaml")
    }

    @Test("start parses service arguments and the shared project options")
    func startParsesArguments() throws {
        let cmd = try ComposeStart.parse(["--cwd", "/tmp", "web"])
        #expect(cmd.services == ["web"])
        #expect(cmd.project.cwd == "/tmp")
    }
}
