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
//  ComposeKill.swift
//  Container-Compose
//
//  `kill [SERVICE...]`: sends a signal to containers, SIGKILL by default.
//

import ArgumentParser
import ContainerCommands
import ContainerAPIClient
import Foundation
import Yams

public struct ComposeKill: AsyncParsableCommand {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "kill",
        abstract: "Force-stop service containers by sending a signal"
    )

    @Argument(help: "Specify the services to kill")
    var services: [String] = []

    @Option(name: [.customShort("s"), .customLong("signal")], help: "Signal to send to the container(s)")
    var signal: String = "SIGKILL"

    @OptionGroup
    var project: ComposeProjectOptions

    /// Maps a signal name (`TERM` or `SIGTERM`) or number to its signal number.
    ///
    /// - Returns: The signal number, or SIGKILL (9) for unrecognized names.
    static func signalNumber(for raw: String) -> Int32 {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        if let number = Int32(trimmed) {
            return number
        }

        var name = trimmed.uppercased()
        if name.hasPrefix("SIG") {
            name = String(name.dropFirst(3))
        }

        switch name {
        case "KILL": return 9
        case "TERM": return 15
        case "INT": return 2
        case "HUP": return 1
        case "QUIT": return 3
        default: return 9
        }
    }

    public func run() async throws {
        let resolved = try project.resolve(filteringBy: services)
        let defined: [(serviceName: String, service: Service)] = resolved.compose.services.compactMap { name, svc in
            svc.map { (name, $0) }
        }
        try Service.validateRequestedServices(services, against: defined)

        // Kill only named services; the shared selection adds dependencies.
        let selected = services.isEmpty
            ? resolved.services
            : resolved.services.filter { services.contains($0.serviceName) }

        let client = ContainerClient()
        let snapshots = (try? await client.list()) ?? []
        let signalNumber = Self.signalNumber(for: signal)

        // Reverse order: dependents stop before their dependencies.
        for target in selected.reversed() {
            let container = snapshots.first { snapshot in
                target.matches(containerID: snapshot.id, labels: snapshot.configuration.labels, projectName: resolved.projectName)
            }
            guard let container else {
                print("Warning: No container found for service '\(target.serviceName)', skipping.")
                continue
            }

            print("Killing container: \(container.id) (signal: \(signal))")
            do {
                try await client.kill(id: container.id, signal: String(signalNumber))
                print("Successfully killed container: \(container.id)")
            } catch {
                print("Error Killing Container: \(error)")
            }
        }
    }
}
