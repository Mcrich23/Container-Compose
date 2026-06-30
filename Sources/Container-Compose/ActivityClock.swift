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

import Foundation

/// Thread-safe timestamp of the most recent output from a service's
/// `container run` subprocess. Written from the streaming `Task` and read by
/// the readiness wait to tell "slow but progressing" apart from "stuck".
///
/// The clock is injectable so the idle-window logic can be exercised in tests
/// without leaning on real wall-clock time.
final class ActivityClock: @unchecked Sendable {
    private let lock = NSLock()
    private let now: @Sendable () -> Date
    private var _lastActivity: Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        self._lastActivity = now()
    }

    func touch() {
        lock.lock()
        _lastActivity = now()
        lock.unlock()
    }

    var lastActivity: Date {
        lock.lock()
        defer { lock.unlock() }
        return _lastActivity
    }
}
