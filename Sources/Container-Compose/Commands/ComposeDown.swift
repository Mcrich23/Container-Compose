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
//  ComposeDown.swift
//  Container-Compose
//
//  Created by Morris Richman on 6/19/25.
//

import ArgumentParser
import ContainerCommands
import ContainerAPIClient
import Foundation
import Yams

public struct ComposeDown: AsyncParsableCommand {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "down",
        abstract: "Stop containers with compose"
    )

    @Argument(help: "Specify the services to stop")
    var services: [String] = []

    @OptionGroup
    var projectOptions: ComposeProjectOptions

    private var fileManager: FileManager { FileManager.default }

    public func run() async throws {
        let project = try projectOptions.resolve(filteringBy: services)

        if project.compose.name != nil {
            print("Info: Docker Compose project name parsed as: \(project.projectName)")
            print(
                "Note: The 'name' field currently only affects container naming (e.g., '\(project.projectName)-serviceName'). Full project-level isolation for other resources (networks, implicit volumes) is not implemented by this tool."
            )
        } else {
            print("Info: No 'name' field found in docker-compose.yml. Using directory name as project name: \(project.projectName)")
        }

        // A service excluded by an inactive profile may still be running from a
        // previous `up --profile ...` that isn't repeated on this `down` — warn
        // instead of silently skipping it.
        if services.isEmpty {
            let selectedNames = Set(project.services.map(\.serviceName))
            let skipped = project.compose.services.keys.filter { !selectedNames.contains($0) }
            if !skipped.isEmpty {
                print(
                    "Note: not stopping '\(skipped.sorted().joined(separator: "', '"))' — gated by an inactive Compose profile. "
                        + "Pass --profile <name> (or name the service explicitly) to also stop them."
                )
            }
        }

        try await stop(project)
    }

    private func stop(_ project: ComposeProject) async throws {
        let client = ContainerClient()
        for target in project.services {
            // Stop every candidate name that exists — not just the first hit —
            // so a container left behind by a previous run in the other naming
            // mode is cleaned up too.
            var stoppedAny = false
            for name in target.candidateContainerNames {
                guard let container = try? await client.get(id: name) else { continue }
                stoppedAny = true
                print("Stopping container: \(name)")
                do {
                    try await client.stop(id: container.id)
                    print("Successfully stopped container: \(name)")
                } catch {
                    print("Error Stopping Container: \(error)")
                }
            }
            if !stoppedAny {
                print("Warning: No container found for service '\(target.serviceName)' (tried: \(target.candidateContainerNames.joined(separator: ", "))).")
            }

            // Best-effort: the extra_hosts bind-mount source (if any) is only safe
            // to remove once the container that had it mounted is stopped.
            try? fileManager.removeItem(atPath: ComposeUp.extraHostsFilePath(projectName: project.projectName, serviceName: target.serviceName))
        }
    }
}
