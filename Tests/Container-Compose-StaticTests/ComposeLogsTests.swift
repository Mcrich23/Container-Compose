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

@Suite("Compose logs Tests")
struct ComposeLogsTests {

    @Test("logs parses service arguments and output flags")
    func logsParsesArguments() throws {
        let cmd = try ComposeLogs.parse(["--follow", "--tail", "25", "--no-color", "--no-log-prefix", "web", "db"])
        #expect(cmd.follow)
        #expect(cmd.tail == 25)
        #expect(cmd.noColor)
        #expect(cmd.noLogPrefix)
        #expect(cmd.services == ["web", "db"])
    }

    @Test("logs defaults: not following, full tail, color, prefixes")
    func logsDefaults() throws {
        let cmd = try ComposeLogs.parse([])
        #expect(!cmd.follow)
        #expect(cmd.tail == nil)
        #expect(!cmd.noColor)
        #expect(!cmd.noLogPrefix)
    }

    @Test("-f remains the shared --file flag, not --follow")
    func fFlagStaysFile() throws {
        let cmd = try ComposeLogs.parse(["-f", "my-compose.yaml"])
        #expect(cmd.project.composeFileOptions.composeFilename == "my-compose.yaml")
        #expect(!cmd.follow)
    }
}
