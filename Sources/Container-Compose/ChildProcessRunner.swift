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

/// Spawns a child process, streams its output, and tracks it in an
/// ``ActiveProcessRegistry`` so interrupts can signal and verify it.
enum ChildProcessRunner {
    /// How the child's stdin is wired.
    enum Stdin: Sendable {
        /// `/dev/null`: the child sees EOF immediately (no `stdin_open`).
        case null
        /// An open pipe nothing ever writes to, closed when the child exits. Mirrors
        /// `docker compose up` for `stdin_open: true`: an interactive image (`CMD bash`)
        /// blocks on stdin instead of exiting on EOF. The host's own stdin and terminal
        /// are never shared with the child.
        case heldOpen

        /// `stdin_open: true` services keep stdin open; everything else gets EOF.
        init(stdinOpen: Bool?) { self = stdinOpen == true ? .heldOpen : .null }
    }

    /// Runs `executable`, streams stdout/stderr through the closures, and returns
    /// the exit status once the process terminates.
    @discardableResult
    static func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        stdin: Stdin = .null,
        registry: ActiveProcessRegistry = .shared,
        onStdout: @escaping @Sendable (String) -> Void,
        onStderr: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        // Interrupted before launch: don't start anything the shutdown can't see.
        if registry.isShuttingDown { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            let stdinPipe: Pipe?
            switch stdin {
            case .null:
                stdinPipe = nil
                process.standardInput = FileHandle.nullDevice
            case .heldOpen:
                stdinPipe = Pipe()
                process.standardInput = stdinPipe
            }
            if let environment { process.environment = environment }

            let stdoutHandle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading

            stdoutHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let string = String(data: data, encoding: .utf8) { onStdout(string) }
            }
            stderrHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let string = String(data: data, encoding: .utf8) { onStderr(string) }
            }

            process.terminationHandler = { proc in
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil
                try? stdinPipe?.fileHandleForWriting.close()  // no-op if already closed
                registry.unregister(proc.processIdentifier)
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
                // The child owns the read end now; keeping ours open leaks one fd per child.
                try? stdinPipe?.fileHandleForReading.close()
                registry.register(process.processIdentifier, closeStdin: stdinPipe.map { pipe in
                    { try? pipe.fileHandleForWriting.close() }
                })
                // Shutdown began between the check above and the spawn: reap it now.
                if registry.isShuttingDown { kill(process.processIdentifier, SIGKILL) }
                // A fast child can finish before register(): its termination handler already
                // ran unregister(), so drop the entry we just added or it goes stale.
                if !process.isRunning { registry.unregister(process.processIdentifier) }
            } catch {
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil
                try? stdinPipe?.fileHandleForReading.close()
                try? stdinPipe?.fileHandleForWriting.close()
                continuation.resume(throwing: error)
            }
        }
    }
}
