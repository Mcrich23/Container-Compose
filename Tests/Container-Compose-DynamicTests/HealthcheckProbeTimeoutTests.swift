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

/// The probe timeout against a real `container exec`.
///
/// The static suite drives `streamCommand` with host `sleep`, which dies on
/// SIGTERM. `container exec` does not: while the process it proxies is stuck it
/// survives the signal, so a probe timeout that only calls `terminate()` never
/// returns and `up` stalls instead of recording one failed attempt. That
/// difference is invisible to any test using a host process, which is why this
/// one needs a container.
@Suite("Healthcheck Probe Timeout - Real container exec", .containerDependent, .serialized)
struct HealthcheckProbeTimeoutTests {

    private static let probeTimeout: TimeInterval = 2
    /// The exec sleeps far longer than the timeout, so returning at all means the
    /// timeout ended it rather than the command finishing.
    private static let execSleepSeconds = 300

    @Test("a hung container exec is killed by the probe timeout")
    func hungExecIsKilledByTimeout() async throws {
        let name = "probe-timeout-\(UUID().uuidString.prefix(8).lowercased())"
        let dir = URL.temporaryDirectory.appending(path: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let yaml = """
        name: \(name)
        services:
          victim:
            image: alpine:latest
            command: ["sleep", "600"]
        """
        try yaml.write(to: dir.appending(path: "docker-compose.yaml"), atomically: false, encoding: .utf8)

        var composeUp = try ComposeUp.parse(["-d", "--cwd", dir.path(percentEncoded: false)])
        try await composeUp.run()

        // Torn down on both paths and awaited. A `defer` cannot hold the async
        // call, and spawning a detached Task from one leaves the container behind
        // whenever the test finishes first -- measured.
        func tearDown() async {
            var down = try? ComposeDown.parse(["--cwd", dir.path(percentEncoded: false)])
            try? await down?.run()
            // `down` stops the container but leaves it listed, so the suite would
            // accumulate one stopped container per run. Removing it explicitly
            // keeps repeated runs clean.
            _ = try? await ComposeUp
                .parse(["-d", "--cwd", dir.path(percentEncoded: false)])
                .streamCommand(
                    "container",
                    args: ["delete", "-f", "\(name)-victim"],
                    onStdout: { _ in },
                    onStderr: { _ in })
            try? FileManager.default.removeItem(at: dir)
        }

        let composeCommand = try ComposeUp.parse(["-d", "--cwd", dir.path(percentEncoded: false)])
        let start = ContinuousClock.now
        let outcome: CommandOutcome
        do {
            outcome = try await composeCommand.streamCommand(
                "container",
                args: ["exec", "\(name)-victim", "sleep", "\(Self.execSleepSeconds)"],
                timeout: Self.probeTimeout,
                onStdout: { _ in },
                onStderr: { _ in }
            )
        } catch {
            await tearDown()
            throw error
        }
        let elapsed = ContinuousClock.now - start
        await tearDown()

        // Without the SIGKILL escalation this call does not return and the test
        // times out rather than failing here.
        #expect(elapsed < .seconds(Self.execSleepSeconds / 2))
        #expect(outcome.timedOut)
        #expect(!outcome.succeeded)
    }
}
