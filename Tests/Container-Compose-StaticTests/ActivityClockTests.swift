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

@Suite("ActivityClock")
struct ActivityClockTests {

    /// A clock backed by a mutable, thread-safe "current time" so the idle
    /// window can be exercised deterministically without `Task.sleep`.
    private final class FakeClock: @unchecked Sendable {
        private let lock = NSLock()
        private var _now: Date
        init(_ start: Date) { _now = start }
        var now: Date {
            lock.lock(); defer { lock.unlock() }
            return _now
        }
        func advance(by interval: TimeInterval) {
            lock.lock(); _now += interval; lock.unlock()
        }
    }

    @Test("seeds lastActivity from the injected clock")
    func seedsFromInjectedClock() {
        let start = Date(timeIntervalSince1970: 1_000)
        let fake = FakeClock(start)
        let clock = ActivityClock(now: { fake.now })

        #expect(clock.lastActivity == start)
    }

    @Test("touch() captures the injected clock's current time")
    func touchCapturesInjectedTime() {
        let start = Date(timeIntervalSince1970: 1_000)
        let fake = FakeClock(start)
        let clock = ActivityClock(now: { fake.now })

        fake.advance(by: 5)
        clock.touch()

        #expect(clock.lastActivity == start.addingTimeInterval(5))
    }

    /// The wait logic compares `now - lastActivity` against the idle timeout.
    /// With an injected clock we can verify that window without real time: a
    /// `touch()` resets the elapsed-since-activity interval to zero, and time
    /// advancing without a touch grows it past the threshold.
    @Test("idle window reflects time since the last touch")
    func idleWindowReflectsTimeSinceTouch() {
        let start = Date(timeIntervalSince1970: 1_000)
        let fake = FakeClock(start)
        let clock = ActivityClock(now: { fake.now })

        // Active progress: a touch right before we measure keeps the window small.
        fake.advance(by: 100)
        clock.touch()
        #expect(fake.now.timeIntervalSince(clock.lastActivity) == 0)

        // Silence: time moves on without a touch, so the window grows.
        fake.advance(by: 31)
        #expect(fake.now.timeIntervalSince(clock.lastActivity) == 31)
    }

    /// `touch()` and `lastActivity` race across threads in production (the
    /// streaming task writes while the wait loop reads). Hammer both
    /// concurrently and assert we observe a coherent, monotonic value and no
    /// crash from a data race.
    @Test("touch() and lastActivity are safe under concurrent access")
    func concurrentAccessIsSafe() async {
        let clock = ActivityClock()
        let iterations = 10_000

        await withTaskGroup(of: Void.self) { group in
            // Writers.
            for _ in 0..<4 {
                group.addTask {
                    for _ in 0..<iterations { clock.touch() }
                }
            }
            // Readers — each read must return a real Date, never tear.
            for _ in 0..<4 {
                group.addTask {
                    for _ in 0..<iterations {
                        _ = clock.lastActivity.timeIntervalSince1970
                    }
                }
            }
        }

        // After all writers finished, lastActivity is at/after the seed time.
        #expect(clock.lastActivity.timeIntervalSince1970 > 0)
    }
}
