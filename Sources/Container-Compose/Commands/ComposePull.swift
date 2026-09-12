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
//  ComposePull.swift
//  Container-Compose
//

import ArgumentParser
import ContainerCommands
import ContainerAPIClient
import Foundation
import Yams

public struct ComposePull: AsyncParsableCommand {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "pull",
        abstract: "Pull images for services defined in a compose file"
    )

    @Argument(help: "Services to pull (pulls all if omitted)")
    var services: [String] = []

    @Flag(name: .long, help: "Also pull images for the services that requested services depend on")
    var includeDeps: Bool = false

    @OptionGroup
    var project: ComposeProjectOptions

    @OptionGroup
    var logging: Flags.Logging

    public mutating func run() async throws {
        let resolved = try project.resolve(filteringBy: services)

        // Fail fast on a typo'd/unknown service name — same contract #139
        // established for `up` ("no such service: <svc>").
        let defined: [(serviceName: String, service: Service)] = resolved.compose.services.compactMap { name, service in
            service.map { (name, $0) }
        }
        try Service.validateRequestedServices(services, against: defined)

        let environment = loadEnvFile(path: project.envFilePath)

        for target in Self.pullTargets(in: resolved, requested: services, includeDeps: includeDeps) {
            guard let image = Self.resolvedImage(for: target.service, environment: environment) else {
                // Build-only services have no image to pull; compose builds these.
                print("Skipping \(target.serviceName) (no image, built from a Dockerfile)")
                continue
            }

            print("Pulling \(target.serviceName) (\(image))...")
            try await pullImage(image, platform: target.service.platform)
        }
    }

    /// The services `pull` acts on. The shared selection expands `depends_on`
    /// (which `up` needs to start dependencies), but `docker compose pull
    /// <svc>` pulls only the named services unless `--include-deps` is passed —
    /// so explicit requests are narrowed back to the requested names.
    static func pullTargets(
        in project: ComposeProject,
        requested: [String],
        includeDeps: Bool
    ) -> [ComposeProject.ServiceTarget] {
        guard !requested.isEmpty, !includeDeps else { return project.services }
        return project.services.filter { requested.contains($0.serviceName) }
    }

    /// The image reference to pull for a service, with `${VAR}` /
    /// `${VAR:-default}` placeholders resolved from the environment file —
    /// a literal `${...}` is not a valid registry reference. `nil` for
    /// build-only services (no `image:` key).
    static func resolvedImage(for service: Service, environment: [String: String]) -> String? {
        service.image.map { resolveVariable($0, with: environment) }
    }

    private func pullImage(_ imageName: String, platform: String?) async throws {
        // Always pull, even when a matching image exists locally: refreshing a
        // moving tag like `:latest` is the point of an explicit `pull`.
        // (`up`'s implicit pull is the place for the already-present shortcut.)
        var commands = [imageName]
        if let platform {
            commands.append(contentsOf: ["--platform", platform])
        }

        let imagePull = try Application.ImagePull.parse(commands + logging.passThroughCommands())
        try await imagePull.run()
    }
}
