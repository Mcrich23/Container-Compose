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

import ArgumentParser
import ContainerAPIClient
import ContainerCommands

public struct ComposePort: AsyncParsableCommand {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "port",
        abstract: "Print the host address and port for a published service port"
    )

    enum Transport: String, ExpressibleByArgument {
        case tcp
        case udp
    }

    @Argument(help: "The service to query")
    var service: String

    @Argument(help: "The container port to look up")
    var privatePort: UInt16

    @Option(name: .customLong("protocol"), help: "Transport protocol (tcp or udp)")
    var transport: Transport = .tcp

    @OptionGroup
    var project: ComposeProjectOptions

    public func validate() throws {
        guard privatePort > 0 else {
            throw ValidationError("The container port must be between 1 and 65535.")
        }
    }

    public func run() async throws {
        let resolved = try project.resolve(filteringBy: [service])
        guard let target = resolved.services.first(where: { $0.serviceName == service }) else {
            throw ComposeError.noSuchService(service)
        }

        let snapshots = try await ContainerClient().list()
        guard let snapshot = snapshots.first(where: {
            $0.status == .running && target.matches(
                containerID: $0.id, labels: $0.configuration.labels, projectName: resolved.projectName)
        }) else {
            throw ValidationError("Service '\(service)' has no running container.")
        }

        let endpoints = snapshot.configuration.publishedPorts.lazy
            .filter { $0.proto.rawValue == self.transport.rawValue }
            .compactMap { binding in
                Self.publishedPort(
                    for: self.privatePort, containerStart: binding.containerPort,
                    hostStart: binding.hostPort, count: binding.count
                ).map { Self.endpoint(host: "\(binding.hostAddress)", port: $0) }
            }
        guard let endpoint = endpoints.first else {
            throw ValidationError("Service '\(service)' has no published port for \(privatePort)/\(transport.rawValue).")
        }
        print(endpoint)
    }

    static func publishedPort(for port: UInt16, containerStart: UInt16, hostStart: UInt16, count: UInt16) -> UInt16? {
        guard hostStart > 0, port >= containerStart else { return nil }
        let offset = port - containerStart
        guard offset < count else { return nil }
        return UInt16(exactly: Int(hostStart) + Int(offset))
    }

    static func endpoint(host: String, port: UInt16) -> String {
        let address = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "\(address):\(port)"
    }
}
