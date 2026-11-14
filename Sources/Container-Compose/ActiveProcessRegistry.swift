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

/// Tracks child processes spawned by container-compose so an interrupt can signal them,
/// close their held-open stdin, and verify they are gone. ``ChildProcessRunner`` is the
/// only place that registers/unregisters, and always unregisters on exit.
final class ActiveProcessRegistry: @unchecked Sendable {
    static let shared = ActiveProcessRegistry()
    private let lock = NSLock()
    private var activePids: Set<pid_t> = []
    private var stdinClosers: [pid_t: () -> Void] = [:]
    private var shuttingDown = false

    /// Once set, ``ChildProcessRunner`` refuses to spawn: a child launched after the
    /// interrupt began would never be signalled and would stall the shutdown.
    var isShuttingDown: Bool { lock.withLock { shuttingDown } }

    func beginShutdown() { lock.withLock { shuttingDown = true } }

    /// - Parameter closeStdin: closes this child's held-open stdin, if it has one.
    func register(_ pid: pid_t, closeStdin: (() -> Void)? = nil) {
        lock.withLock {
            activePids.insert(pid)
            stdinClosers[pid] = closeStdin
        }
    }

    func unregister(_ pid: pid_t) {
        lock.withLock {
            activePids.remove(pid)
            stdinClosers[pid] = nil
        }
    }

    /// Closes every held-open child stdin: interactive children (`CMD bash`) see EOF and
    /// exit on their own, the equivalent of Ctrl-D, long before a stop grace period ends.
    func closeAllHeldStdin() {
        let closers = lock.withLock { () -> [() -> Void] in
            defer { stdinClosers = [:] }
            return Array(stdinClosers.values)
        }
        closers.forEach { $0() }
    }

    func signalAll(_ sig: Int32) {
        let pids = lock.withLock { activePids }
        for pid in pids { kill(pid, sig) }
    }

    func count() -> Int { lock.withLock { activePids.count } }
}
