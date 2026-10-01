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
        let outcome = try await composeUp.streamCommand(
            "sleep",
            args: ["30"],
            timeout: 1,
            onStdout: { _ in },
            onStderr: { _ in }
        )
        let elapsed = ContinuousClock.now - start

        // Generous window: the point is "well under 30s", not millisecond accuracy.
        #expect(elapsed < .seconds(15))
        #expect(outcome.status != 0)
        #expect(outcome.timedOut)
        #expect(!outcome.succeeded)
    }

    /// A probe that finishes inside its timeout must be reported verbatim.
    @Test("streamCommand leaves a fast child alone")
    func streamCommandDoesNotKillFastChild() async throws {
        let composeUp = try ComposeUp.parse(["-d", "--cwd", NSTemporaryDirectory()])

        let outcome = try await composeUp.streamCommand(
            "true",
            args: [],
            timeout: 10,
            onStdout: { _ in },
            onStderr: { _ in }
        )

        #expect(outcome.status == 0)
        #expect(!outcome.timedOut)
        #expect(outcome.succeeded)
    }

    /// The case the exit status cannot answer on its own: a probe that installs a
    /// signal handler and exits 0 when terminated. It overran its timeout and was
    /// killed, so it is not healthy — but `status == 0` says otherwise, which is
    /// why the timeout is carried in the outcome rather than inferred.
    @Test("a probe that traps the signal and exits 0 is not healthy")
    func timedOutProbeExitingZeroIsNotHealthy() async throws {
        let composeUp = try ComposeUp.parse(["-d", "--cwd", NSTemporaryDirectory()])

        let outcome = try await composeUp.streamCommand(
            "sh",
            args: ["-c", "trap 'exit 0' TERM; sleep 30"],
            timeout: 1,
            onStdout: { _ in },
            onStderr: { _ in }
        )

        #expect(outcome.status == 0)      // it really did exit cleanly
        #expect(outcome.timedOut)         // but only because we signalled it
        #expect(!outcome.succeeded)       // so the probe failed
    }

    /// `timeout` has a Compose default of 30s; an omitted value must not be
    /// read as "no timeout".
    @Test("Omitted healthcheck timeout falls back to the Compose default")
    func omittedTimeoutUsesDefault() throws {
        let healthcheck = Healthcheck(test: ["CMD", "true"])
        #expect(Healthcheck.parseDuration(healthcheck.timeout, default: 30) == 30)
    }
}

/// The waiting policy `healthcheck` applies, exercised through `awaitHealthy`'s
/// injected probe and clock so no daemon is involved.
@Suite("Healthcheck Waiting Policy")
struct HealthcheckWaitingPolicyTests {

    /// Drives `awaitHealthy` with a scripted probe, a fake clock the sleeps
    /// advance, and a record of what it was asked. Nothing here waits.
    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [Bool]
        private var _calls = 0
        private var _sleeps: [TimeInterval] = []
        private var _time: TimeInterval = 0

        init(_ results: [Bool]) { self.results = results }

        func next() -> Bool {
            lock.lock(); defer { lock.unlock() }
            _calls += 1
            return results.isEmpty ? false : results.removeFirst()
        }

        /// Sleeping is the only thing that moves the clock, which is what makes
        /// the window deterministic without making it a count of iterations.
        func recordSleep(_ seconds: TimeInterval) {
            lock.lock(); defer { lock.unlock() }
            _sleeps.append(seconds)
            _time += seconds
        }

        func now() -> TimeInterval {
            lock.lock(); defer { lock.unlock() }
            return _time
        }

        var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }
        var sleeps: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return _sleeps }
    }

    /// `start_period` is a grace window, not a delay: a probe that comes up
    /// inside it ends the wait there and then. Without that, a service that is
    /// ready in one second still waits out the whole window.
    @Test("a probe that succeeds inside start_period returns immediately")
    func earlySuccessDuringStartPeriod() async throws {
        let probe = Probe([true])

        let healthy = try await ComposeUp.awaitHealthy(
            retries: 3, interval: 1, startPeriod: 30,
            probe: { probe.next() },
            sleep: { probe.recordSleep($0) },
            now: { probe.now() })

        #expect(healthy)
        #expect(probe.calls == 1)
        // Returned before sleeping even once, so it did not sit out the window.
        #expect(probe.sleeps.isEmpty)
    }

    /// Failures inside the window must not be charged against `retries`, so the
    /// full retry budget is still available once the window closes. With a 3s
    /// window at 1s intervals the probe fails 3 times inside it and must then
    /// still be given all 3 retries — 6 calls, not 3.
    @Test("failures inside start_period do not consume the retry budget")
    func failuresDuringStartPeriodDoNotConsumeRetries() async throws {
        let probe = Probe([])   // always fails

        let healthy = try await ComposeUp.awaitHealthy(
            retries: 3, interval: 1, startPeriod: 3,
            probe: { probe.next() },
            sleep: { probe.recordSleep($0) },
            now: { probe.now() })

        #expect(!healthy)
        #expect(probe.calls == 6)
    }

    /// The retry budget itself, with no grace window in play.
    @Test("without a start_period the probe is tried exactly retries times")
    func retriesWithoutStartPeriod() async throws {
        let probe = Probe([])

        let healthy = try await ComposeUp.awaitHealthy(
            retries: 2, interval: 1, startPeriod: 0,
            probe: { probe.next() },
            sleep: { probe.recordSleep($0) },
            now: { probe.now() })

        #expect(!healthy)
        #expect(probe.calls == 2)
        // One sleep between the two attempts, and none after the last.
        #expect(probe.sleeps.count == 1)
    }

    /// A probe that recovers after the window still passes on a later retry.
    @Test("a success on the last retry is still healthy")
    func successOnLastRetry() async throws {
        let probe = Probe([false, false, true])

        let healthy = try await ComposeUp.awaitHealthy(
            retries: 3, interval: 1, startPeriod: 0,
            probe: { probe.next() },
            sleep: { probe.recordSleep($0) },
            now: { probe.now() })

        #expect(healthy)
        #expect(probe.calls == 3)
    }
}
