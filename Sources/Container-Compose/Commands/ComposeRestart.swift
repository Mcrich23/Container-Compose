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
//  ComposeRestart.swift
//  Container-Compose
//
//  `restart [SERVICE...]`: stops then starts containers without recreating them.
//

import ArgumentParser
import ContainerCommands
import ContainerAPIClient
import Foundation
import Yams

public struct ComposeRestart: AsyncParsableCommand {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "restart",
        abstract: "Restart service containers (stop then start)"
    )

    @Argument(help: "Specify the services to restart")
    var services: [String] = []

    @OptionGroup
    var project: ComposeProjectOptions

    public func run() async throws {
        let resolved = try project.resolve(filteringBy: services)
        let defined: [(serviceName: String, service: Service)] = resolved.compose.services.compactMap { name, svc in
            svc.map { (name, $0) }
        }
        try Service.validateRequestedServices(services, against: defined)

        // Restart only named services; the shared selection adds dependencies.
        let selected = services.isEmpty
            ? resolved.services
            : resolved.services.filter { services.contains($0.serviceName) }

        let client = ContainerClient()
        let snapshots = (try? await client.list()) ?? []

        for target in selected {
            let container = snapshots.first { snapshot in
                target.matches(containerID: snapshot.id, labels: snapshot.configuration.labels, projectName: resolved.projectName)
            }
            guard let container else {
                print("Warning: No container found for service '\(target.serviceName)', skipping.")
                continue
            }

            print("Restarting container: \(container.id)")
            do {
                try await client.stop(
                    id: container.id,
                    opts: ComposeStopOptions.resolve(for: target.service)
                )
            } catch {
                print("Error Stopping Container: \(error)")
            }

            do {
                // `ContainerClient` has no `start(id:)`.
                let start = try Application.ContainerStart.parse([container.id])
                try await start.run()
                print("Successfully restarted container: \(container.id)")
            } catch let exit as ExitCode where exit == .success {
                // ContainerStart signals completion by throwing ExitCode.success.
                print("Successfully restarted container: \(container.id)")
            } catch {
                print("Error Starting Container: \(error)")
            }
        }
    }
}
