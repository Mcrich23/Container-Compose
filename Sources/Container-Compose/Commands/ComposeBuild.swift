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
//  ComposeBuild.swift
//  Container-Compose
//
//  Created by Luke Parkin on 04/20/26.
//

import ArgumentParser
import ContainerCommands
import ContainerAPIClient
import ContainerizationExtras
import Foundation
import Yams

public struct ComposeBuild: AsyncParsableCommand, @unchecked Sendable {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "build",
        abstract: "Build images from a compose file without starting containers"
    )

    @Argument(help: "Services to build (builds all if omitted)")
    var services: [String] = []

    @OptionGroup
    var projectOptions: ComposeProjectOptions

    @Flag(name: .long, help: "Do not use cache when building")
    var noCache: Bool = false

    @OptionGroup
    var logging: Flags.Logging

    private var composeDirectory: String { projectOptions.composeDirectory }

    public mutating func run() async throws {
        // Shared resolution routes both the explicit-service-name and default
        // cases through the same selection `up`/`down` use: an explicit name
        // (or the default profile-eligible set) pulls in its `depends_on` graph
        // regardless of that dependency's own build/profile status. Without
        // this, a dependency only reachable via `depends_on` — whether
        // profile-gated or just not named explicitly — would be started by
        // `up` but never get built here.
        let project = try projectOptions.resolve(filteringBy: services)
        let environmentVariables = loadEnvFile(path: projectOptions.envFilePath)

        let servicesToBuild = project.services.filter { $0.service.build != nil }

        if servicesToBuild.isEmpty {
            print("No services with a 'build' configuration found.")
            return
        }

        print("Building services")
        for target in servicesToBuild {
            try await buildService(
                target.service.build!, for: target.service, serviceName: target.serviceName,
                projectName: project.projectName, environmentVariables: environmentVariables)
        }
        print("Build complete")
    }

    private func buildService(
        _ buildConfig: Build,
        for service: Service,
        serviceName: String,
        projectName: String,
        environmentVariables: [String: String]
    ) async throws {
        let imageTag = service.image ?? "\(serviceName):latest"

        // Per Compose spec: `context` is relative to the compose file's directory,
        // and `dockerfile` is relative to the resolved `context` (not the compose dir).
        let contextURL = URL(fileURLWithPath: buildConfig.context, relativeTo: URL(fileURLWithPath: composeDirectory))
        var commands = [contextURL.path]

        for (key, value) in buildConfig.args ?? [:] {
            commands.append(contentsOf: ["--build-arg", "\(key)=\(resolveVariable(value, with: environmentVariables))"])
        }

        commands.append(contentsOf: [
            "--file", URL(fileURLWithPath: buildConfig.dockerfile ?? "Dockerfile", relativeTo: contextURL).path,
            "--tag", imageTag,
        ])

        if noCache {
            commands.append("--no-cache")
        }

        let split = service.platform?.split(separator: "/")
        let os = String(split?.first ?? "linux")
        let arch = String(((split ?? []).count >= 1 ? split?.last : nil) ?? "arm64")
        commands.append(contentsOf: ["--os", os, "--arch", arch])

        let cpuCount = Int64(service.deploy?.resources?.limits?.cpus ?? "2") ?? 2
        let memoryLimit = service.deploy?.resources?.limits?.memory ?? "2048MB"
        commands.append(contentsOf: ["--cpus", "\(cpuCount)", "--memory", memoryLimit])

        print("\n----------------------------------------")
        print("Building \(serviceName) -> \(imageTag)")
        var buildCommand = try Application.BuildCommand.parse(commands + logging.passThroughCommands())
        try buildCommand.validate()
        try await buildCommand.run()
        print("Built \(serviceName) successfully.")
        print("----------------------------------------")
    }
}
