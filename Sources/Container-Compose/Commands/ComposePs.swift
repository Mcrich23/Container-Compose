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
//  ComposePs.swift
//  Container-Compose
//
//  Implements the `ps` subcommand, which lists the state of a compose
//  project's containers.
//

import ArgumentParser
import ContainerCommands
import ContainerAPIClient
import Foundation
import Yams

public struct ComposePs: AsyncParsableCommand {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "ps",
        abstract: "List containers for this compose project"
    )

    @Argument(help: "Specify the services to list")
    var services: [String] = []

    @Flag(
        name: [.customShort("a"), .customLong("all")],
        help: "Show all containers (default shows just running)")
    var all: Bool = false

    @OptionGroup
    var project: ComposeProjectOptions

    public func run() async throws {
        let resolved = try project.resolve(filteringBy: services)
        try Self.validateRequestedServices(services, in: resolved)

        let client = ContainerClient()
        let snapshots = try await client.list()

        // A service's container is matched primarily by the compose labels
        // `up` stamps (reliable regardless of naming mode), falling back to
        // the candidate names for containers created before the labels
        // existed. Dependency order from the resolved project is preserved;
        // containers that don't exist yet simply don't appear.
        let ordered = resolved.services.flatMap { target in
            snapshots.filter { snapshot in
                let labels = snapshot.configuration.labels
                if labels["com.docker.compose.project"] == resolved.projectName {
                    return labels["com.docker.compose.service"] == target.serviceName
                }
                return target.candidateContainerNames.contains(snapshot.id)
            }
        }
        let visible = all ? ordered : ordered.filter { $0.status == .running }

        let header = ["NAME", "IMAGE", "STATUS", "PORTS"]
        let rows = visible.map { snapshot in
            [
                snapshot.id,
                snapshot.configuration.image.reference,
                snapshot.status.rawValue,
                // Render published ports like `docker compose ps`:
                // `0.0.0.0:8080->80/tcp`. Avoids naming the `PublishPort` type
                // (not re-exported into this module) by mapping inline.
                snapshot.configuration.publishedPorts
                    .map { "\($0.hostAddress):\($0.hostPort)->\($0.containerPort)/\($0.proto.rawValue)" }
                    .joined(separator: ", "),
            ]
        }
        print(TableFormatter.render(header: header, rows: rows))
    }
}

extension ComposePs {
    /// Fail fast on a typo'd/unknown service name, matching
    /// `docker compose ps <svc>` ("no such service: <svc>") — same contract
    /// #139 established for `up`.
    static func validateRequestedServices(_ requested: [String], in project: ComposeProject) throws {
        let defined: [(serviceName: String, service: Service)] = project.compose.services.compactMap { name, service in
            service.map { (name, $0) }
        }
        try Service.validateRequestedServices(requested, against: defined)
    }
}
