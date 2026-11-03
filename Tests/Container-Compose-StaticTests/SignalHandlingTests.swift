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

@Suite("Signal Handling and Child Process Tracking Tests", .serialized)
struct SignalHandlingTests {

    @Test("ActiveProcessRegistry registers and unregisters PIDs")
    func processRegistryRegistration() throws {
        let registry = ActiveProcessRegistry()
        #expect(registry.count() == 0)

        // Launch two real sleep processes
        let proc1 = Process()
        proc1.executableURL = URL(fileURLWithPath: "/bin/sleep")
        proc1.arguments = ["10"]
        try proc1.run()
        defer { proc1.terminate() }

        let proc2 = Process()
        proc2.executableURL = URL(fileURLWithPath: "/bin/sleep")
        proc2.arguments = ["10"]
        try proc2.run()
        defer { proc2.terminate() }

        let pid1 = proc1.processIdentifier
        let pid2 = proc2.processIdentifier

        registry.register(pid1)
        registry.register(pid2)
        #expect(registry.count() == 2)

        registry.unregister(pid1)
        #expect(registry.count() == 1)

        registry.unregister(pid2)
        #expect(registry.count() == 0)
    }

    @Test("ActiveProcessRegistry signals child processes")
    func processRegistrySignalsChild() async throws {
        let registry = ActiveProcessRegistry()

        // Launch a sleep child process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()

        let pid = process.processIdentifier
        registry.register(pid)
        #expect(registry.count() == 1)
        #expect(process.isRunning)

        // Signal with SIGINT
        registry.signalAll(SIGINT)

        // Wait for process to exit
        let deadline = Date().addingTimeInterval(3.0)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(!process.isRunning)
        registry.unregister(pid)
        #expect(registry.count() == 0)
    }

    @Test("ActiveProcessRegistry prunes completed processes automatically")
    func processRegistryPrunesCompleted() async throws {
        let registry = ActiveProcessRegistry()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.1"]
        try process.run()

        let pid = process.processIdentifier
        registry.register(pid)
        #expect(registry.count() == 1)

        // Wait for sleep process to naturally exit
        try await Task.sleep(nanoseconds: 250_000_000) // 250ms

        // Calling count() or activeProcesses() automatically prunes dead processes
        #expect(registry.count() == 0)
        #expect(registry.activeProcesses().isEmpty)
    }

    @Test("child spawned after the signal stream is installed still dies on forwarded SIGINT")
    func childDoesNotInheritIgnoredSigint() async throws {
        // Regression guard, not a fix: an ignored SIGINT survives exec and would make `container run`
        // immune to the SIGINT we forward. Foundation's Process currently resets dispositions for
        // children (verified empirically); this fails if that ever stops being true.
        signal(SIGINT, SIG_IGN)

        let registry = ActiveProcessRegistry()
        let started = Date()
        let exit = Task {
            try await ChildProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"],
                registry: registry,
                onStdout: { _ in }, onStderr: { _ in }
            )
        }
        while registry.count() == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        registry.signalAll(SIGINT)
        _ = try await exit.value
        #expect(Date().timeIntervalSince(started) < 2.0)
        #expect(registry.count() == 0)
    }

    @Test("child with held-open stdin does not see EOF; null stdin does")
    func heldOpenStdinKeepsInteractiveChildAlive() async throws {
        // `cat` exits immediately on EOF. A service with `stdin_open: true` (e.g. CMD bash)
        // must stay alive like under `docker compose up`, so stdin has to stay open.
        for (mode, shouldStayAlive) in [(ChildProcessRunner.Stdin.heldOpen, true), (.null, false)] {
            let registry = ActiveProcessRegistry()
            let exit = Task {
                try await ChildProcessRunner.run(
                    executable: URL(fileURLWithPath: "/bin/cat"),
                    arguments: [],
                    stdin: mode,
                    registry: registry,
                    onStdout: { _ in }, onStderr: { _ in }
                )
            }
            try await Task.sleep(nanoseconds: 500_000_000)
            #expect((registry.count() == 1) == shouldStayAlive, "mode \(mode)")
            registry.signalAll(SIGTERM)
            _ = try await exit.value
            #expect(registry.count() == 0)
        }
    }

    @Test("closing held stdin on interrupt lets an interactive child exit without any signal")
    func closeHeldStdinEndsInteractiveChild() async throws {
        let registry = ActiveProcessRegistry()
        let exit = Task {
            try await ChildProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/cat"), arguments: [],
                stdin: .heldOpen, registry: registry,
                onStdout: { _ in }, onStderr: { _ in }
            )
        }
        while registry.count() == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(registry.count() == 1)

        let started = Date()
        registry.closeAllHeldStdin()

        #expect(try await exit.value == 0)
        #expect(Date().timeIntervalSince(started) < 3.0)
        #expect(registry.count() == 0)
    }

    @Test("pty stdin gives the child a real terminal that is private to it, held open until closed")
    func ptyStdinIsATerminalForTheChild() async throws {
        // `container run -t -i` calls setraw() on its own stdin, which only works on a tty.
        // A pty keeps that raw mode off the host terminal, so Ctrl-C still reaches us.
        let registry = ActiveProcessRegistry()
        let output = LockedBuffer()
        let exit = Task {
            try await ChildProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "test -t 0 && echo is-a-tty; cat"],
                stdin: .pty, registry: registry,
                onStdout: { output.append($0) }, onStderr: { _ in }
            )
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(output.value.contains("is-a-tty"))
        #expect(registry.count() == 1, "a pty stdin stays open like heldOpen")

        registry.closeAllHeldStdin()  // EOF-equivalent (hangup) ends the child
        _ = try await exit.value
        #expect(registry.count() == 0)
    }

    @Test("stdin mode follows stdin_open and tty")
    func stdinModeMapping() {
        #expect(ChildProcessRunner.Stdin(stdinOpen: nil, tty: nil) == .null)
        #expect(ChildProcessRunner.Stdin(stdinOpen: false, tty: true) == .null)
        #expect(ChildProcessRunner.Stdin(stdinOpen: true, tty: nil) == .heldOpen)
        #expect(ChildProcessRunner.Stdin(stdinOpen: true, tty: true) == .pty)
    }

    @Test("fast-exiting children never leave stale PIDs tracked (PID-reuse safety)")
    func fastChildrenLeaveNoStalePids() async throws {
        let registry = ActiveProcessRegistry()
        for _ in 0..<100 {
            _ = try await ChildProcessRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [],
                registry: registry, onStdout: { _ in }, onStderr: { _ in }
            )
        }
        // Unpruned count: a stale entry would survive here even though the PID is dead.
        #expect(registry.trackedPidCount == 0)
    }
}

private final class LockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func append(_ s: String) { lock.lock(); text += s; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return text }
}
