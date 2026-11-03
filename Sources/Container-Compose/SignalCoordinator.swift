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

/// Coordinates signal interception across the entire lifecycle of `up`, managing
/// graceful teardown, concurrent container stopping, process cleanup, and verification.
actor SignalCoordinator {
    static let shared = SignalCoordinator()

    private let backend: ContainerBackend
    private let registry: ActiveProcessRegistry
    private let signalSource: @Sendable ([Int32]) -> AsyncStream<Int32>
    private let output: @Sendable (String) -> Void
    private let exit: @Sendable (Int32) -> Void
    private let graceTimeoutSeconds: Double

    /// Lifecycle of interrupt handling; only ever moves forward, except `listening` ⇄ `idle`.
    private enum Phase {
        /// Not listening for signals.
        case idle
        /// Listening; no interrupt received yet.
        case listening
        /// First interrupt received: graceful stop and verification in flight.
        case stopping
        /// Second interrupt received: SIGKILLing everything.
        case forcing
    }

    private var phase: Phase = .idle
    private var firstSignal: Int32 = SIGINT
    private var containerTargets: [ComposeContainerStopTarget] = []
    private var signalTask: Task<Void, Never>?

    init(
        backend: ContainerBackend = LiveContainerBackend(),
        registry: ActiveProcessRegistry = .shared,
        signalSource: @escaping @Sendable ([Int32]) -> AsyncStream<Int32> = { SignalCoordinator.makeSignalStream($0) },
        output: @escaping @Sendable (String) -> Void = { print($0); fflush(stdout) },
        exit: @escaping @Sendable (Int32) -> Void = { Foundation.exit($0) },
        graceTimeoutSeconds: Double = 5.0
    ) {
        self.backend = backend
        self.registry = registry
        self.signalSource = signalSource
        self.output = output
        self.exit = exit
        self.graceTimeoutSeconds = graceTimeoutSeconds
    }

    /// An `AsyncStream` of the given signals, delivered via `DispatchSource` so
    /// they're received even after the disposition has been set to `SIG_IGN`.
    private static func makeSignalStream(_ signals: [Int32]) -> AsyncStream<Int32> {
        AsyncStream { continuation in
            let queue = DispatchQueue(label: "container-compose.signals")
            let sources: [DispatchSourceSignal] = signals.map { sig in
                // Ignore the default action so the DispatchSource alone handles it.
                signal(sig, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
                source.setEventHandler { continuation.yield(sig) }
                source.resume()
                return source
            }
            continuation.onTermination = { _ in sources.forEach { $0.cancel() } }
        }
    }

    func setStopTargets(_ targets: [ComposeContainerStopTarget]) {
        self.containerTargets = targets
    }

    func ensureStarted() {
        guard phase == .idle else { return }
        phase = .listening
        let signals = signalSource([SIGINT, SIGTERM])
        signalTask = Task {
            for await sig in signals {
                // Each signal is handled in its own task: the first handler can sit in a
                // long graceful stop, and a second Ctrl-C must still be serviced meanwhile.
                Task { await self.handleSignal(sig) }
            }
        }
    }

    /// Exits with `code` unless an interrupt shutdown is in flight, in which case the
    /// shutdown owns the exit (and its exit code). Returns whether it exited.
    @discardableResult
    func exitNormally(_ code: Int32, message: String? = nil) -> Bool {
        guard phase == .idle || phase == .listening else { return false }
        if let message { output(message) }
        exit(code)
        return true
    }

    func stopMonitoring() {
        // A shutdown already in flight keeps running and keeps listening for the force signal.
        guard phase == .listening else { return }
        signalTask?.cancel()
        signalTask = nil
        phase = .idle
    }

    func handleSignal(_ sig: Int32) async {
        // Cancelling the listener task doesn't recall a signal already delivered to it,
        // hence `.idle` is ignored; `.forcing` has nothing left to escalate to.
        switch phase {
        case .idle, .forcing: return
        case .listening: await gracefulShutdown(sig)
        case .stopping: await forceStop()
        }
    }

    private func gracefulShutdown(_ sig: Int32) async {
        phase = .stopping
        firstSignal = sig
        registry.beginShutdown()
        let signalName = sig == SIGTERM ? "SIGTERM" : "SIGINT (Ctrl+C)"
        output("\n⚠️  Received \(signalName). Initiating graceful shutdown...")
        output("⚠️  Send another Ctrl+C to force kill immediately (SIGKILL).")

        // Step 1: Forward signal to tracked child processes immediately
        let alive = registry.count()
        if alive > 0 { output("Stopping \(alive) active child process\(alive == 1 ? "" : "es")...") }
        registry.closeAllHeldStdin()
        registry.signalAll(SIGINT)

        let targets = containerTargets

        // Step 2: Concurrently request graceful container stop via daemon
        if !targets.isEmpty {
            output("Stopping containers...")
            await backend.stop(targets)
        }

        // Step 3: Verify and enforce that all child processes and containers are stopped
        guard phase == .stopping else { return }
        output("Verifying all containers and child processes have stopped...")
        await verifyAndEnforceStopped(targets.map(\.containerName))

        guard phase == .stopping else { return }
        output("Shutdown complete.")
        exit(128 + sig)
    }

    private func forceStop() async {
        phase = .forcing
        output("\n🛑 Second interrupt received! Forcing immediate stop with SIGKILL...")

        // Step 1: Force kill all child processes immediately
        registry.signalAll(SIGKILL)

        // Step 2: Force kill all containers
        await backend.kill(containerTargets.map(\.containerName))

        output("Forced stop complete.")
        exit(128 + firstSignal)
    }

    /// Waits (against one shared deadline) for tracked child processes to exit and
    /// containers to stop, then SIGKILLs whatever is still alive.
    private func verifyAndEnforceStopped(_ containerNames: [String]) async {
        let deadline = Date().addingTimeInterval(graceTimeoutSeconds)
        var unstopped: [String] = []
        while true {
            unstopped = await backend.runningContainers(among: containerNames)
            if unstopped.isEmpty && registry.count() == 0 { return }
            if Date() >= deadline { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        registry.signalAll(SIGKILL)
        if !unstopped.isEmpty {
            await backend.kill(unstopped)
        }
    }
}
