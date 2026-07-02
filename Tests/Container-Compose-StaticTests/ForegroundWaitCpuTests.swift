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
    /// Method: take a `getrusage(RUSAGE_SELF)` snapshot, spawn a child Task that
    /// calls `runForegroundUntilStopped` (with no services, so it just awaits the
    /// signal stream and starts no container monitor), sleep for a 1s wall-clock
    /// window, take a second snapshot, and compare user-CPU consumed.
    ///
    /// On the original bug (`for await _ in AsyncStream<Void>(unfolding: {})`),
    /// the child task pinned one core, so over a 1s window it consumes ~1,000,000
    /// µs (one full core). The wait now suspends on a `DispatchSource` signal
    /// stream and consumes essentially nothing.
    ///
    /// `getrusage(RUSAGE_SELF)` is process-wide, so the other (fast, parallel)
    /// static suites add CPU noise — but they finish within the first few hundred
    /// ms, whereas a busy-loop runs the entire second. The 1s window plus a
    /// 400,000 µs threshold (≈0.4 core-seconds) sits well above that transient
    /// noise yet well below a full core's worth of spinning, so the test is
    /// reliable in the full parallel suite, not just in isolation.
    ///
    /// Side effect: this test leaks one suspended task per invocation
    /// (`runForegroundUntilStopped` is `-> Never` and the suspended task can't be
    /// cancelled from outside). The leak is bounded — each leaked task holds only
    /// its stack — and is cleaned up when the test process exits.
    @Test("foreground wait does not pin a CPU core (regression for #27)")
    func foregroundWaitDoesNotPinCpu() async throws {
        let composeUp = ComposeUp()
        let before = userCpuMicroseconds()

        // Detached so cancellation propagation from the test doesn't reach it
        // (it wouldn't matter — the function ignores cancellation by contract —
        // but this makes the leak explicit rather than incidental).
        Task.detached {
            await composeUp.runForegroundUntilStopped(serviceNames: [])
        }

        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1s

        let after = userCpuMicroseconds()
        let consumed = after - before

        #expect(consumed < 400_000,
                "foreground wait consumed \(consumed) µs of user CPU in 1s — likely busy-looping (regression for #27)")
    }
}
