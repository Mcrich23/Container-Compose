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

    @Option(name: [.customShort("f"), .customLong("file")], help: "The path to your Docker Compose file")
    var composeFilename: String?

    @Flag(name: .long, help: "Do not use cache when building")
    var noCache: Bool = false

    @OptionGroup
    var process: Flags.Process

    @OptionGroup
    var logging: Flags.Logging

    private var cwd: String { process.cwd ?? FileManager.default.currentDirectoryPath }

    private var cwdURL: URL { URL(fileURLWithPath: cwd) }

    private static let supportedComposeFilenames = [
        "compose.yml",
        "compose.yaml",
        "docker-compose.yml",
        "docker-compose.yaml",
    ]

    private var composePath: String {
        if let composeFilename {
            return resolvedPath(for: composeFilename, relativeTo: cwdURL)
        }
        for filename in Self.supportedComposeFilenames {
            let candidate = cwdURL.appending(path: filename).path
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        return cwdURL.appending(path: Self.supportedComposeFilenames[0]).path
    }

    private var composeDirectory: String {
        URL(fileURLWithPath: composePath).deletingLastPathComponent().path
    }

    private var envFilePath: String {
        let envFile = process.envFile.first ?? ".env"
        return resolvedPath(for: envFile, relativeTo: cwdURL)
    }

    public mutating func run() async throws {
        guard let yamlData = FileManager.default.contents(atPath: composePath) else {
            let dir = URL(fileURLWithPath: composePath).deletingLastPathComponent().path
            throw YamlError.composeFileNotFound(dir)
        }

        let dockerComposeString = String(data: yamlData, encoding: .utf8)!
        let dockerCompose = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)
        let environmentVariables = loadEnvFile(path: envFilePath)

        let projectName: String
        if let name = dockerCompose.name {
            projectName = name
        } else {
            projectName = deriveProjectName(cwd: cwd)
        }

        var servicesToBuild: [(serviceName: String, service: Service)] = dockerCompose.services.compactMap { name, service in
            guard let service, service.build != nil else { return nil }
            return (name, service)
        }

        if !services.isEmpty {
            servicesToBuild = servicesToBuild.filter { services.contains($0.serviceName) }
        }

        if servicesToBuild.isEmpty {
            print("No services with a 'build' configuration found.")
            return
        }

        print("Building services")
        for (serviceName, service) in servicesToBuild {
            try await buildService(service.build!, for: service, serviceName: serviceName, projectName: projectName, environmentVariables: environmentVariables)
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

        var commands = [URL(fileURLWithPath: buildConfig.context, relativeTo: URL(fileURLWithPath: composeDirectory)).path]

        for (key, value) in buildConfig.args ?? [:] {
            commands.append(contentsOf: ["--build-arg", "\(key)=\(resolveVariable(value, with: environmentVariables))"])
        }

        commands.append(contentsOf: [
            "--file", URL(fileURLWithPath: buildConfig.dockerfile ?? "Dockerfile", relativeTo: URL(fileURLWithPath: composeDirectory)).path,
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
        let buildCommand = try Application.BuildCommand.parse(commands + logging.passThroughCommands())
        try buildCommand.validate()
        try await buildCommand.run()
        print("Built \(serviceName) successfully.")
        print("----------------------------------------")
    }
}
