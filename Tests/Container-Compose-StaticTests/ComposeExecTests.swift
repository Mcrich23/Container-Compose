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

@Suite("Compose exec Tests")
struct ComposeExecTests {

    @Test("exec parses service and passthrough command")
    func execParsesServiceAndCommand() throws {
        let cmd = try ComposeExec.parse(["web", "sh", "-c", "echo hi"])
        #expect(cmd.service == "web")
        #expect(cmd.command == ["sh", "-c", "echo hi"])
    }

    @Test("Flags after the command pass through to the command, not exec")
    func execPassthroughKeepsCommandFlags() throws {
        let cmd = try ComposeExec.parse(["web", "ls", "-la", "/data"])
        #expect(cmd.command == ["ls", "-la", "/data"])
    }

    @Test("exec accepts the shared project options and --index parity no-op")
    func execParsesProjectOptions() throws {
        let cmd = try ComposeExec.parse(["--index", "2", "-f", "my-compose.yaml", "web", "true"])
        #expect(cmd.index == 2)
        #expect(cmd.project.composeFileOptions.composeFilename == "my-compose.yaml")
    }

    @Test("exec requires a command argument")
    func execRequiresCommand() {
        #expect(throws: (any Error).self) {
            _ = try ComposeExec.parse(["web"])
        }
    }
}
