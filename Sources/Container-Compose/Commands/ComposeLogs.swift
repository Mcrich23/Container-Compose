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
        abstract: "View output from containers",
        discussion: """
            Within this subcommand, -f means --follow (matching `docker compose \
            logs -f`). To point at a specific compose file, use --file after the \
            subcommand, or `container-compose -f <file> logs ...` before it.
            """
    )

    @Argument(help: "Specify the services to show logs for. Defaults to all services.")
    var services: [String] = []

    // Long-only: `-f` is `--file`. ArgumentScoping maps `logs -f` here.
    @Flag(name: .customLong("follow"), help: "Follow log output (also: -f)")
    var follow: Bool = false

    @Option(name: .customLong("tail"), help: "Number of lines to show from the end of the logs for each container")
    var tail: Int?

    @Flag(name: .customLong("no-color"), help: "Produce monochrome output")
    var noColor: Bool = false

    @Flag(name: .customLong("no-log-prefix"), help: "Don't print prefix in logs")
    var noLogPrefix: Bool = false

    @OptionGroup
    var project: ComposeProjectOptions

    // Matches `up`'s palette.
    private static let availableContainerConsoleColors: [NamedColor] = [
        .blue, .cyan, .magenta, .lightBlack, .lightBlue, .lightCyan, .lightYellow, .yellow, .lightGreen, .green,
    ]

    public func run() async throws {
        // SIGPIPE is already ignored on some client paths; ignore it always and
        // detect the closed pipe in `emit` so `logs -f | head` exits.
        signal(SIGPIPE, SIG_IGN)

        let resolved = try project.resolve(filteringBy: services)
        let defined: [(serviceName: String, service: Service)] = resolved.compose.services.compactMap { name, svc in
            svc.map { (name, $0) }
        }
        try Service.validateRequestedServices(services, against: defined)

        // Show only named services; the shared selection adds dependencies.
        let selected = services.isEmpty
            ? resolved.services
            : resolved.services.filter { services.contains($0.serviceName) }

        guard !selected.isEmpty else {
            print("No services to show logs for.")
            return
        }

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

        let prefixWidth = targets.map(\.serviceName.count).max() ?? 0

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
                    // Piped stdout is block-buffered; flush for live output.
                    fflush(stdout)
                    // Reader closed the pipe; children exit on their own SIGPIPE.
                    if ferror(stdout) != 0 {
                        Foundation.exit(0)
                    }
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
