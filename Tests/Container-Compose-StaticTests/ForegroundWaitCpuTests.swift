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
import Darwin
@testable import ContainerComposeCore

@Suite("Foreground wait CPU usage", .serialized)
struct ForegroundWaitCpuTests {

    /// Returns user-mode CPU time consumed by this process, in microseconds.
    private func userCpuMicroseconds() -> Int64 {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int64(usage.ru_utime.tv_sec) * 1_000_000 + Int64(usage.ru_utime.tv_usec)
    }

    /// Regression for #27: the foreground `up` wait must suspend, not busy-loop.
    ///
    /// Method: `getrusage(RUSAGE_SELF)` is process-wide, not per-task — it counts
    /// every thread in the process, including whatever other tests Swift Testing
    /// is running concurrently in this same process (this suite is `.serialized`
    /// internally, but that doesn't stop *other* suites from overlapping it). So
    /// rather than an absolute threshold, take a baseline measurement over an
    /// idle 200ms window immediately before the real one, then assert on the
    /// *incremental* cost the foreground-wait task adds on top of that baseline.
    /// This cancels out ambient noise from concurrent tests instead of assuming
    /// it's near-zero, which stopped holding once the suite grew large enough
    /// that something is almost always running during any given 200ms window.
    ///
    /// On the original bug (`for await _ in AsyncStream<Void>(unfolding: {})`),
    /// the child task pins one core, so it adds roughly 200,000 µs of user CPU
    /// on top of baseline during the 200ms window. The wait now suspends on a
    /// `DispatchSource` signal stream (with no containers, so it starts no
    /// container monitor) and adds essentially nothing.
    ///
    /// Threshold of 50,000 µs of *incremental* cost gives ~4× headroom while
    /// still reliably catching a single core's worth of busy-loop work.
    ///
    /// Side effect: this test leaks one suspended task per invocation
    /// (`runForegroundUntilStopped` is `-> Never` and the suspended task can't be
    /// cancelled from outside). The leak is bounded — each leaked task holds only
    /// its stack — and is cleaned up when the test process exits.
    @Test("foreground wait does not pin a CPU core (regression for #27)")
    func foregroundWaitDoesNotPinCpu() async throws {
        let composeUp = ComposeUp()

        // Baseline: ambient CPU consumed by the whole process over an idle
        // 200ms window (no foreground-wait task running), to calibrate against
        // whatever else is concurrently running in this test process.
        let baselineBefore = userCpuMicroseconds()
        try await Task.sleep(nanoseconds: 200_000_000)  // 200ms
        let baselineConsumed = userCpuMicroseconds() - baselineBefore

        let before = userCpuMicroseconds()

        // Detached so cancellation propagation from the test doesn't reach it
        // (it wouldn't matter — the function ignores cancellation by contract —
        // but this makes the leak explicit rather than incidental).
        Task.detached {
            await composeUp.runForegroundUntilStopped(containerNames: [])
        }

        try await Task.sleep(nanoseconds: 200_000_000)  // 200ms

        let after = userCpuMicroseconds()
        let consumed = after - before
        let incremental = consumed - baselineConsumed

        #expect(incremental < 50_000,
                "foreground wait added \(incremental) µs of user CPU over a \(baselineConsumed) µs baseline in 200ms — likely busy-looping (regression for #27)")
    }
}
