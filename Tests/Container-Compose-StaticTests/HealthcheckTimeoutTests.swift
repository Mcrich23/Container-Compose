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
@testable import ContainerComposeCore

@Suite("Healthcheck Timeout Tests")
struct HealthcheckTimeoutTests {

    /// `healthcheck.timeout` is only useful if an overrunning probe is actually
    /// killed. Without the timeout the child below runs for its full 30s and
    /// exits 0, so this test fails on both counts.
    @Test("streamCommand terminates a child that overruns its timeout")
    func streamCommandHonoursTimeout() async throws {
        let composeUp = try ComposeUp.parse(["-d", "--cwd", NSTemporaryDirectory()])

        let start = ContinuousClock.now
        let exitCode = try await composeUp.streamCommand(
            "sleep",
            args: ["30"],
            timeout: 1,
            onStdout: { _ in },
            onStderr: { _ in }
        )
        let elapsed = ContinuousClock.now - start

        // Generous window: the point is "well under 30s", not millisecond accuracy.
        #expect(elapsed < .seconds(15))
        #expect(exitCode != 0)
    }

    /// A probe that finishes inside its timeout must be reported verbatim.
    @Test("streamCommand leaves a fast child alone")
    func streamCommandDoesNotKillFastChild() async throws {
        let composeUp = try ComposeUp.parse(["-d", "--cwd", NSTemporaryDirectory()])

        let exitCode = try await composeUp.streamCommand(
            "true",
            args: [],
            timeout: 10,
            onStdout: { _ in },
            onStderr: { _ in }
        )

        #expect(exitCode == 0)
    }

    /// `timeout` has a Compose default of 30s; an omitted value must not be
    /// read as "no timeout".
    @Test("Omitted healthcheck timeout falls back to the Compose default")
    func omittedTimeoutUsesDefault() throws {
        let healthcheck = Healthcheck(test: ["CMD", "true"])
        #expect(Healthcheck.parseDuration(healthcheck.timeout, default: 30) == 30)
    }
}
