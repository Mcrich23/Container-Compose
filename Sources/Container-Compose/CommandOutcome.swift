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

/// How a child process ended.
///
/// The exit status alone cannot answer "did this command succeed", because a
/// process that installs a signal handler and exits 0 when terminated reports
/// the same status as one that finished its work. A healthcheck probe that does
/// that would be recorded as healthy while it was in fact killed for overrunning
/// its timeout, so whether the timeout fired is carried alongside the status
/// rather than inferred from it.
public struct CommandOutcome: Sendable, Equatable {
    /// The process's exit status, as reported by the kernel.
    public let status: Int32
    /// Whether this command was terminated for exceeding its timeout.
    public let timedOut: Bool

    public init(status: Int32, timedOut: Bool) {
        self.status = status
        self.timedOut = timedOut
    }

    /// A command succeeded only if it exited cleanly *and* was left alone to do it.
    public var succeeded: Bool { status == 0 && !timedOut }
}

/// A one-way flag the timeout callback sets and the termination handler reads.
/// Both run on arbitrary dispatch queues, so the write has to be synchronised.
final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
