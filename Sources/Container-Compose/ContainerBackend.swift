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

import ContainerAPIClient
import Foundation

/// Everything the interrupt path needs from the container runtime. Abstracted so the
/// shutdown choreography can be tested with a fake runtime (no XPC daemon required).
protocol ContainerBackend: Sendable {
    /// Gracefully stops (without removing) the targets concurrently, honouring each
    /// target's stop timeout. Returns once the runtime has finished stopping them.
    func stop(_ targets: [ComposeContainerStopTarget]) async
    /// Force-stops the named containers with SIGKILL.
    func kill(_ names: [String]) async
    /// The subset of `names` whose containers currently exist and are running.
    func runningContainers(among names: [String]) async -> [String]
}

/// ContainerBackend backed by the Apple Container XPC daemon.
struct LiveContainerBackend: ContainerBackend {
    func stop(_ targets: [ComposeContainerStopTarget]) async {
        let timeouts = Dictionary(targets.map { ($0.containerName, $0.timeoutInSeconds) }, uniquingKeysWith: { first, _ in first })
        await forEachExistingContainer(Array(timeouts.keys)) { client, name, id in
            print("Stopping container: \(name)")
            fflush(stdout)
            do {
                try await client.stop(
                    id: id,
                    opts: ComposeStopOptions.resolve(timeoutInSeconds: timeouts[name] ?? 0)
                )
            } catch {
                print("Error stopping container \(name): \(error)")
                fflush(stdout)
            }
        }
    }

    func kill(_ names: [String]) async {
        await forEachExistingContainer(names) { client, name, id in
            print("Killing container: \(name)")
            fflush(stdout)
            try? await client.kill(id: id, signal: "SIGKILL")
        }
    }

    func runningContainers(among names: [String]) async -> [String] {
        let client = ContainerClient()
        var running: [String] = []
        for name in names {
            if let container = try? await client.get(id: name), container.status == .running {
                running.append(name)
            }
        }
        return running
    }

    /// Runs `body` concurrently for each named container that exists, skipping the rest.
    private func forEachExistingContainer(
        _ names: [String],
        _ body: @escaping @Sendable (ContainerClient, _ name: String, _ id: String) async -> Void
    ) async {
        let client = ContainerClient()
        await withTaskGroup(of: Void.self) { group in
            for name in names {
                group.addTask {
                    guard let container = try? await client.get(id: name) else { return }
                    await body(client, name, container.id)
                }
            }
        }
    }
}
