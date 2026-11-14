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

@Suite("Argument Scoping Tests")
struct ArgumentScopingTests {
    // Stable subcommand set so tests don't depend on the live configuration.
    let subs: Set<String> = ["up", "down", "build", "logs", "version", "help"]

    func normalize(_ argv: [String]) -> [String] {
        normalizeScopedFlags(argv, subcommands: subs)
    }

    @Test("`-f` after logs becomes `--follow`")
    func followShortInLogsScope() {
        #expect(normalize(["logs", "-f"]) == ["logs", "--follow"])
        #expect(normalize(["logs", "-f", "web"]) == ["logs", "--follow", "web"])
    }

    @Test("Root `-f <file>` is preserved (file flag, not follow)")
    func rootFileFlagPreserved() {
        #expect(normalize(["-f", "compose.yml", "logs"]) == ["-f", "compose.yml", "logs"])
    }

    @Test("File before subcommand AND follow after both resolve")
    func fileBeforeFollowAfter() {
        #expect(
            normalize(["-f", "compose.yml", "logs", "-f"])
                == ["-f", "compose.yml", "logs", "--follow"]
        )
    }

    @Test("A root file value equal to a subcommand name is not the boundary")
    func valueLookingLikeSubcommand() {
        // `-f` consumes `up` as its value; `logs` is the real subcommand.
        #expect(normalize(["-f", "up", "logs", "-f"]) == ["-f", "up", "logs", "--follow"])
    }

    @Test("Subcommands without an override are untouched")
    func otherSubcommandsUntouched() {
        #expect(normalize(["up", "-f", "compose.yml"]) == ["up", "-f", "compose.yml"])
        #expect(normalize(["down", "-f"]) == ["down", "-f"])
    }

    @Test("`--` ends rewriting; trailing `-f` is passed through verbatim")
    func doubleDashTerminator() {
        #expect(normalize(["logs", "--", "-f"]) == ["logs", "--", "-f"])
        #expect(
            normalize(["logs", "web", "--", "-f", "x"]) == ["logs", "web", "--", "-f", "x"]
        )
    }

    @Test("Long flags and other options pass through unchanged")
    func longFlagsUntouched() {
        #expect(
            normalize(["logs", "--tail", "5", "-f"]) == ["logs", "--tail", "5", "--follow"]
        )
        #expect(normalize(["logs", "--follow"]) == ["logs", "--follow"])
    }

    @Test("Attached/combined short forms are left as-is (documented limitation)")
    func attachedFormsUntouched() {
        // Only an exact `-f` token is rewritten; `-ffoo`/`-fd` are not expanded.
        #expect(normalize(["logs", "-fd"]) == ["logs", "-fd"])
    }

    @Test("`help <subcommand>` is not rewritten")
    func helpSubcommand() {
        // The active subcommand is `help`, which has no overrides.
        #expect(normalize(["help", "logs"]) == ["help", "logs"])
    }

    @Test("No subcommand: arguments are unchanged")
    func noSubcommand() {
        #expect(normalize(["--help"]) == ["--help"])
        #expect(normalize([]) == [])
    }

    @Test("Live configuration exposes logs as a known subcommand")
    func subcommandNamesDerivedFromConfiguration() {
        #expect(Main.subcommandNames.contains("logs"))
        #expect(Main.subcommandNames.contains("help"))
    }
}
