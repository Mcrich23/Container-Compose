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

@Suite("waitForever CPU usage")
struct WaitForeverCpuTests {

    /// Returns user-mode CPU time consumed by this process, in microseconds.
    private func userCpuMicroseconds() -> Int64 {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int64(usage.ru_utime.tv_sec) * 1_000_000 + Int64(usage.ru_utime.tv_usec)
    }

    /// Regression for #27: `waitForever()` must suspend, not busy-loop.
    ///
    /// Method: take a `getrusage(RUSAGE_SELF)` snapshot, spawn a child Task
    /// that calls `waitForever()`, sleep for 200ms wall-clock, take a second
    /// snapshot, and compare user-CPU consumed.
    ///
    /// On the bug (`for await _ in AsyncStream<Void>(unfolding: {})`), the
    /// child task pins one core, so user CPU consumed during the 200ms window
    /// is around 200,000 µs (one full core). With the fix
    /// (`withUnsafeContinuation { _ in }`), the child task suspends and
    /// consumes essentially nothing.
    ///
    /// Threshold of 50,000 µs gives ~4× headroom over a noisy CI baseline
    /// (test-runner overhead, parallel tasks) while still reliably catching
    /// a single core's worth of busy-loop work.
    ///
    /// Side effect: this test leaks one suspended task per invocation
    /// (`waitForever` is `-> Never` and the suspended task can't be cancelled
    /// from outside). The leak is bounded — each leaked task holds only its
    /// stack — and is cleaned up when the test process exits.
    @Test("waitForever does not pin a CPU core (regression for #27)")
    func waitForeverDoesNotPinCpu() async throws {
        let composeUp = ComposeUp()
        let before = userCpuMicroseconds()

        // Detached so cancellation propagation from the test doesn't reach it
        // (it wouldn't matter — the function ignores cancellation by contract —
        // but this makes the leak explicit rather than incidental).
        Task.detached {
            await composeUp.waitForever()
        }

        try await Task.sleep(nanoseconds: 200_000_000)  // 200ms

        let after = userCpuMicroseconds()
        let consumed = after - before

        #expect(consumed < 50_000,
                "waitForever consumed \(consumed) µs of user CPU in 200ms — likely busy-looping (regression for #27)")
    }
}
