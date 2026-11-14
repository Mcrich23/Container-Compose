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
//  ComposeStart.swift
//  Container-Compose
//
//  Implements `start [SERVICE...]`: boot existing (stopped) service
//  containers, the counterpart to `stop`.
//

import ArgumentParser
import ContainerCommands
import ContainerAPIClient
import Foundation
import Yams

public struct ComposeStart: AsyncParsableCommand {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "start",
        abstract: "Start existing (stopped) service containers"
    )

    @Argument(help: "Specify the services to start")
    var services: [String] = []

    @OptionGroup
    var project: ComposeProjectOptions

    public func run() async throws {
        let resolved = try project.resolve(filteringBy: services)
        let defined: [(serviceName: String, service: Service)] = resolved.compose.services.compactMap { name, svc in
            svc.map { (name, $0) }
        }
        try Service.validateRequestedServices(services, against: defined)

        // Explicit requests start only the named services, matching
        // `docker compose start <svc>`.
        let selected = services.isEmpty
            ? resolved.services
            : resolved.services.filter { services.contains($0.serviceName) }

        let client = ContainerClient()
        let snapshots = (try? await client.list()) ?? []

        // Start in resolved (dependency) order so dependencies come up first.
        // Containers are found via the shared matching rule: labels are
        // authoritative, candidate names identify only unlabeled pre-label
        // containers.
        for target in selected {
            let container = snapshots.first { snapshot in
                target.matches(containerID: snapshot.id, labels: snapshot.configuration.labels, projectName: resolved.projectName)
            }
            guard let container else {
                print("Warning: No container found for service '\(target.serviceName)', skipping.")
                continue
            }

            print("Starting container: \(container.id)")
            do {
                // There is no `ContainerClient.start(id:)`; reuse the underlying
                // `container start` command, which boots a created/stopped
                // container by id in detached mode.
                let start = try Application.ContainerStart.parse([container.id])
                try await start.run()
                print("Successfully started container: \(container.id)")
            } catch let exit as ExitCode where exit == .success {
                // ContainerStart throws ExitCode on completion; success is fine.
                print("Successfully started container: \(container.id)")
            } catch {
                print("Error Starting Container: \(error)")
            }
        }
    }
}
