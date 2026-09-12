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

        for target in resolved.services {
            let service = target.service
            guard let image = service.image else {
                // Build-only services have no image to pull; compose builds these.
                print("Skipping \(target.serviceName) (no image, built from a Dockerfile)")
                continue
            }

            print("Pulling \(target.serviceName) (\(image))...")
            try await pullImage(image, platform: service.platform)
        }
    }

    private func pullImage(_ imageName: String, platform: String?) async throws {
        // Skip the pull if the image is already present locally. Mirrors the
        // match logic used by `up`: exact reference, registry-prefixed
        // reference, or matching last path component (short references).
        let imageList = try await ClientImage.list()
        let exists = imageList.contains { ref in
            let stored = ref.description.reference
            return stored == imageName
                || stored.hasSuffix("/\(imageName)")
                || stored.components(separatedBy: "/").last == imageName
        }
        guard !exists else {
            print("  Image \(imageName) already present, skipping.")
            return
        }

        var commands = [imageName]
        if let platform {
            commands.append(contentsOf: ["--platform", platform])
        }

        let imagePull = try Application.ImagePull.parse(commands + logging.passThroughCommands())
        try await imagePull.run()
    }
}
