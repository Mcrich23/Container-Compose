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
    func processRegistryRegistration() {
        let registry = ActiveProcessRegistry()
        #expect(registry.count() == 0)

        registry.register(12345)
        registry.register(67890)
        #expect(registry.count() == 2)

        registry.unregister(12345)
        #expect(registry.count() == 1)

        registry.unregister(67890)
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

    @Test("ActiveProcessRegistry waitUntilEmpty waits and cleans up")
    func processRegistryWaitUntilEmpty() async throws {
        let registry = ActiveProcessRegistry()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()

        let pid = process.processIdentifier
        registry.register(pid)

        // Signal with SIGTERM and wait until empty
        registry.signalAll(SIGTERM)
        process.terminationHandler = { proc in
            registry.unregister(proc.processIdentifier)
        }

        await registry.waitUntilEmpty(timeoutSeconds: 3.0)
        #expect(registry.count() == 0)
        #expect(!process.isRunning)
    }

    @Test("makeSignalStream yields signal despite SIG_IGN")
    func signalStreamYieldsSignal() async throws {
        // Explicitly set SIGINT to SIG_IGN beforehand
        signal(SIGINT, SIG_IGN)

        let stream = ComposeUp.makeSignalStream([SIGINT])
        var iterator = stream.makeAsyncIterator()

        // Send SIGINT to self
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            kill(getpid(), SIGINT)
        }

        let received = await iterator.next()
        #expect(received == SIGINT)
    }
}
