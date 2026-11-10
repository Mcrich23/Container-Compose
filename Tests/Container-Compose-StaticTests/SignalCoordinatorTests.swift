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

// MARK: - Test doubles

/// Thread-safe record of everything the coordinator prints/does, with an awaitable exit.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    private var _events: [String] = []
    private var _exitCodes: [Int32] = []

    func line(_ s: String) { lock.withLock { _lines.append(s) } }
    func event(_ s: String) { lock.withLock { _events.append(s) } }
    func exit(_ code: Int32) { lock.withLock { _exitCodes.append(code) } }

    var lines: [String] { lock.withLock { _lines } }
    var output: String { lines.joined(separator: "\n") }
    var events: [String] { lock.withLock { _events } }
    var exitCodes: [Int32] { lock.withLock { _exitCodes } }

    /// Polls until `condition` holds or `timeout` elapses; returns whether it held.
    func wait(timeout: TimeInterval = 5, _ condition: @Sendable () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}

/// Fake container runtime. `stopDelay` simulates a container that ignores SIGTERM until
/// its grace period ends; `stopGate` lets a test hold `stop` open indefinitely.
final class FakeBackend: ContainerBackend, @unchecked Sendable {
    let recorder: Recorder
    private let lock = NSLock()
    private var running: Set<String>
    private let stopDelay: TimeInterval
    private let stubborn: Bool  // stays "running" until killed

    init(recorder: Recorder, running: [String], stopDelay: TimeInterval = 0, stubborn: Bool = false) {
        self.recorder = recorder
        self.running = Set(running)
        self.stopDelay = stopDelay
        self.stubborn = stubborn
    }

    func stop(_ targets: [ComposeContainerStopTarget]) async {
        recorder.event("stop:" + targets.map(\.containerName).sorted().joined(separator: ","))
        if stopDelay > 0 { try? await Task.sleep(nanoseconds: UInt64(stopDelay * 1_000_000_000)) }
        if !stubborn { lock.withLock { running.subtract(targets.map(\.containerName)) } }
    }

    func kill(_ names: [String]) async {
        recorder.event("kill:" + names.sorted().joined(separator: ","))
        lock.withLock { running.subtract(names) }
    }

    func runningContainers(among names: [String]) async -> [String] {
        lock.withLock { names.filter(running.contains) }
    }
}

struct Harness {
    let recorder = Recorder()
    let coordinator: SignalCoordinator
    let signals: AsyncStream<Int32>.Continuation
    let registry: ActiveProcessRegistry

    init(
        backend: (Recorder) -> FakeBackend,
        registry: ActiveProcessRegistry = ActiveProcessRegistry(),
        graceTimeoutSeconds: Double = 1.0
    ) {
        let (stream, continuation) = AsyncStream<Int32>.makeStream()
        let recorder = self.recorder
        self.signals = continuation
        self.registry = registry
        self.coordinator = SignalCoordinator(
            backend: backend(recorder),
            registry: registry,
            signalSource: { _ in stream },
            output: { recorder.line($0) },
            exit: { recorder.exit($0) },
            graceTimeoutSeconds: graceTimeoutSeconds
        )
    }
}

let targetA = ComposeContainerStopTarget(containerName: "proj-a", timeoutInSeconds: 10)
let targetB = ComposeContainerStopTarget(containerName: "proj-b", timeoutInSeconds: 10)


/// A fake `container run`: prints "ready", then runs until signalled (or exits 3 if `crash`).
/// `ignoreSignals` makes it behave like a wedged container CLI (ignores INT/TERM).
enum FakeContainerProcess {
    static func script(ignoreSignals: Bool, crash: Bool = false) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cc-fake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("fake-container.sh")
        let body = """
            #!/bin/sh
            trap \(ignoreSignals ? "''" : "'exit 130'") INT TERM
            echo ready
            \(crash ? "exit 3" : "while true; do sleep 0.05; done")
            """
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// Starts the fake process tracked in `registry`, mirroring each output line into `recorder`.
    static func start(_ script: URL, registry: ActiveProcessRegistry, recorder: Recorder) -> Task<Int32, Error> {
        Task {
            try await ChildProcessRunner.run(
                executable: script, arguments: [], registry: registry,
                onStdout: { recorder.line("child: " + $0) }, onStderr: { recorder.line("child: " + $0) }
            )
        }
    }
}

// MARK: - Tests

@Suite("SignalCoordinator: interrupt behaviour through an injected container backend", .serialized)
struct SignalCoordinatorTests {

    @Test("first SIGINT announces the interrupt, stops registered containers and exits 130")
    func firstSigintStopsContainersAndExits130() async {
        let h = Harness(backend: { FakeBackend(recorder: $0, running: ["proj-a", "proj-b"]) })
        await h.coordinator.setStopTargets([targetA, targetB])
        await h.coordinator.ensureStarted()

        h.signals.yield(SIGINT)

        #expect(await h.recorder.wait { h.recorder.exitCodes == [130] })
        #expect(h.recorder.output.contains("Received SIGINT"))
        #expect(h.recorder.output.contains("Shutdown complete"))
        #expect(h.recorder.events == ["stop:proj-a,proj-b"])
    }

    @Test("second Ctrl-C force-kills immediately even while the graceful stop is still blocked")
    func secondSignalForcesKillWhileStopIsBlocked() async {
        // stop() takes 30s (a container ignoring SIGTERM until its grace period ends).
        let h = Harness(backend: { FakeBackend(recorder: $0, running: ["proj-a"], stopDelay: 30) })
        await h.coordinator.setStopTargets([targetA])
        await h.coordinator.ensureStarted()

        h.signals.yield(SIGINT)
        #expect(await h.recorder.wait { h.recorder.events == ["stop:proj-a"] })

        let secondSent = Date()
        h.signals.yield(SIGINT)

        #expect(await h.recorder.wait(timeout: 2) { h.recorder.exitCodes == [130] })
        #expect(Date().timeIntervalSince(secondSent) < 2)
        #expect(h.recorder.events.contains("kill:proj-a"))
        #expect(h.recorder.output.contains("Second interrupt"))
    }

    @Test("a wedged child and a stubborn container are force-killed within one grace budget")
    func stubbornChildAndContainerEscalateWithinSingleGraceBudget() async throws {
        let grace = 1.0
        let h = Harness(
            backend: { FakeBackend(recorder: $0, running: ["proj-a"], stubborn: true) },
            graceTimeoutSeconds: grace
        )
        let script = try FakeContainerProcess.script(ignoreSignals: true)
        let child = FakeContainerProcess.start(script, registry: h.registry, recorder: h.recorder)
        #expect(await h.recorder.wait { h.recorder.output.contains("ready") })
        await h.coordinator.setStopTargets([targetA])
        await h.coordinator.ensureStarted()

        let sent = Date()
        h.signals.yield(SIGINT)

        #expect(await h.recorder.wait(timeout: 5) { h.recorder.exitCodes == [130] })
        let elapsed = Date().timeIntervalSince(sent)
        // Child wait and container wait share ONE deadline (not 2x grace back to back).
        #expect(elapsed < grace * 1.5, "shutdown took \(elapsed)s")
        #expect(h.recorder.events.contains("kill:proj-a"))
        _ = try await child.value
        #expect(h.registry.count() == 0)
    }

    @Test("SIGTERM is announced as SIGTERM and exits 143 (128 + signal)")
    func sigtermExits143() async {
        let h = Harness(backend: { FakeBackend(recorder: $0, running: ["proj-a"]) })
        await h.coordinator.setStopTargets([targetA])
        await h.coordinator.ensureStarted()

        h.signals.yield(SIGTERM)

        #expect(await h.recorder.wait { h.recorder.exitCodes == [143] })
        #expect(h.recorder.output.contains("Received SIGTERM"))
    }

    @Test("a running child is reaped by an interrupt, promptly even if it ignores signals", arguments: [false, true])
    func interruptReapsChild(wedged: Bool) async throws {
        let grace = 0.4
        let h = Harness(backend: { FakeBackend(recorder: $0, running: ["proj-a"]) }, graceTimeoutSeconds: grace)
        let child = FakeContainerProcess.start(try FakeContainerProcess.script(ignoreSignals: wedged), registry: h.registry, recorder: h.recorder)
        await h.coordinator.setStopTargets([targetA])
        await h.coordinator.ensureStarted()
        #expect(await h.recorder.wait { h.recorder.output.contains("ready") })

        let sent = Date()
        h.signals.yield(SIGINT)

        #expect(await h.recorder.wait(timeout: 5) { h.recorder.exitCodes == [130] })
        #expect(Date().timeIntervalSince(sent) < (wedged ? grace * 1.5 : 0.5))
        _ = try await child.value
        #expect(h.registry.count() == 0, "child leaked")
    }

    @Test("a child that crashed earlier does not stop a later interrupt from completing")
    func interruptAfterChildCrash() async throws {
        let h = Harness(backend: { FakeBackend(recorder: $0, running: ["proj-a"]) })
        let script = try FakeContainerProcess.script(ignoreSignals: false, crash: true)
        #expect(try await FakeContainerProcess.start(script, registry: h.registry, recorder: h.recorder).value == 3)
        #expect(h.registry.count() == 0)
        await h.coordinator.setStopTargets([targetA])
        await h.coordinator.ensureStarted()

        h.signals.yield(SIGINT)

        #expect(await h.recorder.wait { h.recorder.exitCodes == [130] })
        #expect(h.recorder.events == ["stop:proj-a"])
    }

    @Test("an interrupt before any container is known still exits promptly without stopping anything")
    func interruptBeforeTargetsRegistered() async {
        let h = Harness(backend: { FakeBackend(recorder: $0, running: []) })
        await h.coordinator.ensureStarted()

        h.signals.yield(SIGINT)

        #expect(await h.recorder.wait(timeout: 1) { h.recorder.exitCodes == [130] })
        #expect(h.recorder.events.isEmpty)
        #expect(h.recorder.output.contains("Received SIGINT"))
    }

    @Test("a signal after stopMonitoring is ignored (detached up must not be torn down)")
    func noHandlingAfterStopMonitoring() async {
        let h = Harness(backend: { FakeBackend(recorder: $0, running: ["proj-a"]) })
        await h.coordinator.setStopTargets([targetA])
        await h.coordinator.ensureStarted()
        await h.coordinator.stopMonitoring()

        h.signals.yield(SIGINT)
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(h.recorder.exitCodes.isEmpty)
        #expect(h.recorder.events.isEmpty)
    }

    @Test("interrupt closes held stdin so a signal-immune interactive child exits without SIGKILL")
    func interruptClosesHeldStdin() async throws {
        let h = Harness(backend: { FakeBackend(recorder: $0, running: ["proj-a"]) }, graceTimeoutSeconds: 3)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cc-fake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("interactive.sh")
        try "#!/bin/sh\ntrap '' INT TERM\necho ready\ncat > /dev/null\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let registry = h.registry
        let recorder = h.recorder
        let child = Task {
            try await ChildProcessRunner.run(
                executable: script, arguments: [], stdin: .heldOpen, registry: registry,
                onStdout: { recorder.line($0) }, onStderr: { recorder.line($0) }
            )
        }
        #expect(await h.recorder.wait { h.recorder.output.contains("ready") })
        await h.coordinator.setStopTargets([targetA])
        await h.coordinator.ensureStarted()

        let sent = Date()
        h.signals.yield(SIGINT)

        #expect(await h.recorder.wait { h.recorder.exitCodes == [130] })
        #expect(Date().timeIntervalSince(sent) < 1.0)
        #expect(try await child.value == 0, "child should exit via EOF, not be killed")
    }

    @Test("no child process may be spawned once shutdown has begun")
    func spawnRefusedDuringShutdown() async throws {
        // Interrupt lands between "Starting service" and the `container run` spawn.
        let h = Harness(
            backend: { FakeBackend(recorder: $0, running: ["proj-a"], stopDelay: 0.5) },
            graceTimeoutSeconds: 2
        )
        await h.coordinator.setStopTargets([targetA])
        await h.coordinator.ensureStarted()
        h.signals.yield(SIGINT)
        #expect(await h.recorder.wait { h.recorder.events == ["stop:proj-a"] })

        let script = try FakeContainerProcess.script(ignoreSignals: true)
        await #expect(throws: CancellationError.self) {
            _ = try await ChildProcessRunner.run(
                executable: script, arguments: [], registry: h.registry,
                onStdout: { _ in }, onStderr: { _ in }
            )
        }
        #expect(h.registry.count() == 0)
        #expect(await h.recorder.wait { h.recorder.exitCodes == [130] })
    }

    @Test("foreground watcher's normal exit is suppressed while an interrupt shutdown is running")
    func normalExitSuppressedDuringShutdown() async {
        // Closing stdin stops the container, so the "all containers stopped" watcher fires
        // mid-shutdown; it must not exit 0 over the interrupt's 130 / "Shutdown complete".
        let h = Harness(backend: { FakeBackend(recorder: $0, running: ["proj-a"], stopDelay: 0.3) })
        await h.coordinator.setStopTargets([targetA])
        await h.coordinator.ensureStarted()

        #expect(await h.coordinator.exitNormally(0) == true, "no interrupt: normal exit proceeds")
        #expect(h.recorder.exitCodes == [0])

        h.signals.yield(SIGINT)
        #expect(await h.recorder.wait { h.recorder.events == ["stop:proj-a"] })
        #expect(await h.coordinator.exitNormally(0) == false, "interrupt in flight: suppressed")

        #expect(await h.recorder.wait { h.recorder.exitCodes == [0, 130] })
        #expect(h.recorder.output.contains("Shutdown complete"))
    }

    @Test("forced stop after SIGTERM exits 143, matching the graceful path")
    func forcedStopKeepsSignalExitCode() async {
        let h = Harness(backend: { FakeBackend(recorder: $0, running: ["proj-a"], stopDelay: 30) })
        await h.coordinator.setStopTargets([targetA])
        await h.coordinator.ensureStarted()
        h.signals.yield(SIGTERM)
        #expect(await h.recorder.wait { h.recorder.events == ["stop:proj-a"] })

        h.signals.yield(SIGINT)

        #expect(await h.recorder.wait(timeout: 2) { h.recorder.exitCodes == [143] })
    }
}

@Suite("SignalCoordinator default signal source", .serialized)
struct SignalCoordinatorDefaultSourceTests {
    @Test("delivers SIGTERM to the shutdown handler even when it was set to SIG_IGN")
    func defaultSourceReceivesIgnoredSignal() async throws {
        signal(SIGTERM, SIG_IGN)
        let recorder = Recorder()
        let coordinator = SignalCoordinator(
            backend: FakeBackend(recorder: recorder, running: []),
            registry: ActiveProcessRegistry(),
            output: { recorder.line($0) },
            exit: { recorder.exit($0) },
            graceTimeoutSeconds: 0.5
        )
        await coordinator.ensureStarted()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { kill(getpid(), SIGTERM) }

        #expect(await recorder.wait { recorder.exitCodes == [128 + SIGTERM] })
        await coordinator.stopMonitoring()
    }
}
