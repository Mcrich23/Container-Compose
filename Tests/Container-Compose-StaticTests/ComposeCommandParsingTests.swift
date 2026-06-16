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

@Suite("Compose command parsing")
struct ComposeCommandParsingTests {
    @Test("Main+ComposeUp command accepts -f flag for compose file from root")
    func composeUpCommandAcceptsFileFlag() throws {
        let cmd = try Main.parseAsRoot(["-f", "my-compose.yaml", "up"]) as! ComposeUp
        #expect(cmd.composeFileOptions.composeFilename == "my-compose.yaml")
    }

    @Test("Main+ComposeUp command accepts --env-file flag from root")
    func composeUpCommandAcceptsEnvFileFlag() throws {
        let cmd = try Main.parseAsRoot(["--env-file", "custom.env", "up"]) as! ComposeUp
        #expect(cmd.composeFileOptions.envFile == "custom.env")
    }

    @Test("Main+ComposeUp command accepts --env-file flag on subcommand")
    func composeUpCommandAcceptsEnvFileFlagOnSubcommand() throws {
        let cmd = try Main.parseAsRoot(["up", "--env-file", "custom.env"]) as! ComposeUp
        #expect(cmd.composeFileOptions.envFile == "custom.env")
    }

    @Test("Main+ComposeUp command accepts -w flag for workdir")
    func composeUpCommandAcceptsWorkdirFlag() throws {
        let cmd = try Main.parseAsRoot(["-w", "/some/path", "up"]) as! ComposeUp
        #expect(cmd.composeFileOptions.workdir == "/some/path")
    }

    @Test("Main+ComposeDown command accepts --env-file flag")
    func composeDownCommandAcceptsEnvFileFlag() throws {
        let cmd = try Main.parseAsRoot(["--env-file", "prod.env", "down"]) as! ComposeDown
        #expect(cmd.composeFileOptions.envFile == "prod.env")
    }

    @Test("Main+ComposeBuild command accepts --env-file flag")
    func composeBuildCommandAcceptsEnvFileFlag() throws {
        let cmd = try Main.parseAsRoot(["--env-file", "build.env", "build"]) as! ComposeBuild
        #expect(cmd.composeFileOptions.envFile == "build.env")
    }

    @Test("envFile is nil when not specified")
    func envFileDefaultsToNil() throws {
        let cmd = try Main.parseAsRoot(["up"]) as! ComposeUp
        #expect(cmd.composeFileOptions.envFile == nil)
    }

    @Test("workdir is nil when not specified")
    func workdirDefaultsToNil() throws {
        let cmd = try Main.parseAsRoot(["up"]) as! ComposeUp
        #expect(cmd.composeFileOptions.workdir == nil)
    }
}
