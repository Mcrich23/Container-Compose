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

//
//  ComposeStop.swift
//  Container-Compose
//
//  Implements `stop [SERVICE...]`: stop service containers without removing
//  them, so a later `start` can bring them back.
//

import ArgumentParser
import ContainerCommands
import ContainerAPIClient
import Foundation
import Yams

public struct ComposeStop: AsyncParsableCommand {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "stop",
        abstract: "Stop running service containers without removing them"
    )

    @Argument(help: "Specify the services to stop")
    var services: [String] = []

    @OptionGroup
    var project: ComposeProjectOptions

    public func run() async throws {
        let resolved = try project.resolve(filteringBy: services)
        let defined: [(serviceName: String, service: Service)] = resolved.compose.services.compactMap { name, svc in
            svc.map { (name, $0) }
        }
        try Service.validateRequestedServices(services, against: defined)

        // Explicit requests stop only the named services (`docker compose
        // stop <svc>` does not stop dependencies); the shared selection's
        // depends_on expansion is for `up`.
        let selected = services.isEmpty
            ? resolved.services
            : resolved.services.filter { services.contains($0.serviceName) }

        let client = ContainerClient()
        let snapshots = (try? await client.list()) ?? []

        // Stop in reverse dependency order so dependents go down before the
        // services they depend on. Containers are found via the shared
        // matching rule: labels are authoritative, candidate names identify
        // only unlabeled pre-label containers.
        for target in selected.reversed() {
            let container = snapshots.first { snapshot in
                target.matches(containerID: snapshot.id, labels: snapshot.configuration.labels, projectName: resolved.projectName)
            }
            guard let container else {
                print("Warning: No container found for service '\(target.serviceName)', skipping.")
                continue
            }

            print("Stopping container: \(container.id)")
            do {
                try await client.stop(
                    id: container.id,
                    opts: ComposeStopOptions.resolve(for: target.service)
                )
                print("Successfully stopped container: \(container.id)")
            } catch {
                print("Error Stopping Container: \(error)")
            }
        }
    }
}
