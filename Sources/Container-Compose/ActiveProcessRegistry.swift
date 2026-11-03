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
import Darwin

/// Tracks active child processes spawned by container-compose (e.g. attached `container run`
/// subprocesses) so they can be explicitly signaled and verified stopped on external interrupts.
final class ActiveProcessRegistry: @unchecked Sendable {
    static let shared = ActiveProcessRegistry()
    private let lock = NSLock()
    private var activePids: Set<pid_t> = []
    private var stdinClosers: [pid_t: () -> Void] = [:]
    private var shuttingDown = false

    /// Once set, ``ChildProcessRunner`` refuses to spawn: a child launched after the
    /// interrupt began would never be signalled and would stall the shutdown.
    var isShuttingDown: Bool {
        lock.lock()
        defer { lock.unlock() }
        return shuttingDown
    }

    func beginShutdown() {
        lock.lock()
        defer { lock.unlock() }
        shuttingDown = true
    }

    /// - Parameter closeStdin: closes a held-open stdin pipe for this child (see
    ///   ``ChildProcessRunner/Stdin/heldOpen``), if it has one.
    func register(_ pid: pid_t, closeStdin: (() -> Void)? = nil) {
        lock.lock()
        defer { lock.unlock() }
        pruneDeadLocked()
        activePids.insert(pid)
        if let closeStdin { stdinClosers[pid] = closeStdin }
    }

    func unregister(_ pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        activePids.remove(pid)
        stdinClosers[pid] = nil
    }

    /// Closes every held-open child stdin: interactive children (`CMD bash`) see EOF and
    /// exit on their own, the equivalent of Ctrl-D, long before a stop grace period ends.
    func closeAllHeldStdin() {
        lock.lock()
        let closers = Array(stdinClosers.values)
        stdinClosers = [:]
        lock.unlock()
        closers.forEach { $0() }
    }

    /// Checks whether a given PID is still running.
    static func isProcessAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        var status: Int32 = 0
        let waitResult = waitpid(pid, &status, WNOHANG)
        if waitResult == pid {
            return false
        }
        if waitResult == -1 && errno == ECHILD {
            if kill(pid, 0) == -1 && errno == ESRCH {
                return false
            }
        } else if kill(pid, 0) == -1 && errno == ESRCH {
            return false
        }
        return true
    }

    private func pruneDeadLocked() {
        activePids = activePids.filter { Self.isProcessAlive($0) }
        stdinClosers = stdinClosers.filter { activePids.contains($0.key) }
    }

    /// Prunes any completed processes and returns the list of currently alive PIDs.
    func activeProcesses() -> [pid_t] {
        lock.lock()
        defer { lock.unlock() }
        pruneDeadLocked()
        return Array(activePids)
    }

    func signalAll(_ sig: Int32) {
        lock.lock()
        pruneDeadLocked()
        let pids = activePids
        lock.unlock()
        for pid in pids {
            kill(pid, sig)
        }
    }

    /// Number of PIDs currently tracked, WITHOUT pruning dead ones. Lets tests detect
    /// stale entries (which would be dangerous once the OS reuses the PID).
    var trackedPidCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activePids.count
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        pruneDeadLocked()
        return activePids.count
    }

    func waitUntilEmpty(timeoutSeconds: Double) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if count() == 0 { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        signalAll(SIGKILL)
    }
}
