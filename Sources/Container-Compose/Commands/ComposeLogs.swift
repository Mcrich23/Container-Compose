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
//  ComposeLogs.swift
//  Container-Compose
//

import ArgumentParser
import ContainerCommands
import ContainerAPIClient
import Foundation
@preconcurrency import Rainbow
import Yams

public struct ComposeLogs: AsyncParsableCommand, @unchecked Sendable {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "logs",
        abstract: "View output from containers"
    )

    @Argument(help: "Specify the services to show logs for. Defaults to all services.")
    var services: [String] = []

    // Declared long-only because `-f` is owned tool-wide by `--file` (the shared
    // `ComposeFileOptions`, which `logs` also uses for compose-file resolution).
    @Flag(name: .customLong("follow"), help: "Follow log output")
    var follow: Bool = false

    @Option(name: .customLong("tail"), help: "Number of lines to show from the end of the logs for each container")
    var tail: Int?

    @Flag(name: .customLong("no-color"), help: "Produce monochrome output")
    var noColor: Bool = false

    @Flag(name: .customLong("no-log-prefix"), help: "Don't print prefix in logs")
    var noLogPrefix: Bool = false

    @OptionGroup
    var project: ComposeProjectOptions

    // Same palette `up` uses to color per-service output, so a service keeps a
    // consistent look across `up` and `logs`.
    private static let availableContainerConsoleColors: [NamedColor] = [
        .blue, .cyan, .magenta, .lightBlack, .lightBlue, .lightCyan, .lightYellow, .yellow, .lightGreen, .green,
    ]

    public func run() async throws {
        // Resolve the project through the shared options, failing fast on
        // unknown service names per the #139 contract.
        let resolved = try project.resolve(filteringBy: services)
        let defined: [(serviceName: String, service: Service)] = resolved.compose.services.compactMap { name, svc in
            svc.map { (name, $0) }
        }
        try Service.validateRequestedServices(services, against: defined)

        // The shared selection expands `depends_on` for `up`'s sake, but
        // `docker compose logs <svc>` shows only the named services — narrow
        // explicit requests back to the requested names.
        let selected = services.isEmpty
            ? resolved.services
            : resolved.services.filter { services.contains($0.serviceName) }

        guard !selected.isEmpty else {
            print("No services to show logs for.")
            return
        }

        // Each service's container is found via the shared matching rule:
        // labels are authoritative, candidate names identify only unlabeled
        // pre-label containers.
        let client = ContainerClient()
        let snapshots = (try? await client.list()) ?? []
        var targets: [(serviceName: String, containerName: String)] = []
        for target in selected {
            let container = snapshots.first { snapshot in
                target.matches(containerID: snapshot.id, labels: snapshot.configuration.labels, projectName: resolved.projectName)
            }
            guard let container else {
                print("Warning: No container found for service '\(target.serviceName)', skipping.")
                continue
            }
            targets.append((target.serviceName, container.id))
        }

        // Width for padding the service-name prefix so the separators line up.
        let prefixWidth = targets.map(\.serviceName.count).max() ?? 0

        // Assign a stable color per service from the shared palette.
        var colors: [String: NamedColor] = [:]
        for (index, target) in targets.enumerated() {
            colors[target.serviceName] = Self.availableContainerConsoleColors[index % Self.availableContainerConsoleColors.count]
        }

        let cwd = project.cwd
        let follow = self.follow
        let tail = self.tail
        let noColor = self.noColor
        let noLogPrefix = self.noLogPrefix

        await withTaskGroup(of: Void.self) { group in
            for (serviceName, containerName) in targets {
                let color = colors[serviceName] ?? .green

                @Sendable func emit(_ chunk: String) {
                    let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false)
                    for line in lines where !line.isEmpty {
                        if noLogPrefix {
                            print(String(line))
                        } else {
                            let padded = serviceName.padding(toLength: max(prefixWidth, serviceName.count), withPad: " ", startingAt: 0)
                            let prefix = "\(padded) | "
                            let coloredPrefix = noColor ? prefix : prefix.applyingColor(color)
                            print("\(coloredPrefix)\(line)")
                        }
                    }
                    // stdout is block-buffered when redirected/piped; flush so
                    // `--follow` (and `logs | grep`) show output live instead of
                    // in delayed chunks.
                    fflush(stdout)
                }

                var args = ["logs"]
                if follow { args.append("--follow") }
                if let tail { args.append(contentsOf: ["-n", "\(tail)"]) }
                args.append(containerName)

                group.addTask {
                    do {
                        try await streamSubprocess("container", args: args, cwd: cwd, onStdout: emit, onStderr: emit)
                    } catch {
                        print("Error streaming logs for \(serviceName): \(error)")
                    }
                }
            }
        }
    }
}
