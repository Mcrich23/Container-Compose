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
//  ComposeProject.swift
//  Container-Compose
//
//  Shared compose-file/project/service resolution used by the subcommands.
//  `up`/`down`/`build`/`logs` each grew their own copies of this logic; new
//  commands should use this instead of duplicating it again.
//

import ArgumentParser
import ContainerCommands
import ContainerAPIClient
import Foundation
import Yams

/// Common options + resolution for any subcommand that operates on a compose
/// project: locating and decoding the compose file, deriving the project name,
/// and resolving services (in dependency order) to their container names.
///
/// Adopt it with `@OptionGroup var project: ComposeProjectOptions`, then call
/// `try project.resolve()` (optionally filtered by service names) to get a
/// `ComposeProject`.
public struct ComposeProjectOptions: ParsableArguments {
    public init() {}

    @OptionGroup
    public var composeFileOptions: ComposeFileOptions

    @OptionGroup
    public var process: Flags.Process

    /// Compose filenames searched for, in order, when `--file` is not given.
    public static let supportedComposeFilenames = [
        "compose.yml",
        "compose.yaml",
        "docker-compose.yml",
        "docker-compose.yaml",
    ]

    private var fileManager: FileManager { .default }

    /// Working directory the command runs in (`--cwd`, else the process cwd).
    public var cwd: String { process.cwd ?? fileManager.currentDirectoryPath }

    var cwdURL: URL { URL(fileURLWithPath: cwd) }

    /// Absolute path to the compose file: the explicit `--file` if given,
    /// otherwise the first supported filename found in `cwd`, otherwise the
    /// default name (so callers produce a consistent "not found" error).
    public var composePath: String {
        if let composeFilename = composeFileOptions.composeFilename {
            return resolvedPath(for: composeFilename, relativeTo: cwdURL)
        }

        for filename in Self.supportedComposeFilenames {
            let candidate = cwdURL.appending(path: filename).path
            if fileManager.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return cwdURL.appending(path: Self.supportedComposeFilenames[0]).path
    }

    /// Directory containing the compose file (the base for relative `context`,
    /// `env_file`, etc.).
    public var composeDirectory: String {
        URL(fileURLWithPath: composePath).deletingLastPathComponent().path
    }

    /// Reads and decodes the compose file at `composePath`.
    /// - Throws: `YamlError.composeFileNotFound` if the file is missing.
    public func loadCompose() throws -> DockerCompose {
        guard let yamlData = fileManager.contents(atPath: composePath) else {
            let path = URL(fileURLWithPath: composePath).deletingLastPathComponent().path
            throw YamlError.composeFileNotFound(path)
        }
        let dockerComposeString = String(data: yamlData, encoding: .utf8)!
        return try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)
    }

    /// Project name used to namespace containers: the compose `name:` field if
    /// present, otherwise the sanitized working-directory name.
    public func projectName(for compose: DockerCompose) -> String {
        compose.name ?? deriveProjectName(cwd: cwd)
    }

    /// Resolves the project's services in dependency (topological) order,
    /// optionally narrowed to `requested` service names.
    ///
    /// - Parameter requested: Service names to keep; empty means all services.
    /// - Returns: `(serviceName, service)` tuples in start order.
    public func orderedServices(
        of compose: DockerCompose,
        filteringBy requested: [String] = []
    ) throws -> [(serviceName: String, service: Service)] {
        var services: [(serviceName: String, service: Service)] = compose.services.compactMap { serviceName, service in
            guard let service else { return nil }
            return (serviceName, service)
        }
        services = try Service.topoSortConfiguredServices(services)

        guard !requested.isEmpty else { return services }
        return services.filter { requested.contains($0.serviceName) }
    }

    /// One-shot convenience: load the compose file and resolve everything a
    /// command typically needs.
    ///
    /// - Parameter requested: Service names to keep; empty means all services.
    public func resolve(filteringBy requested: [String] = []) throws -> ComposeProject {
        let compose = try loadCompose()
        let projectName = projectName(for: compose)
        let services = try orderedServices(of: compose, filteringBy: requested)

        // Surface requested names that don't match any service, like compose.
        if !requested.isEmpty {
            let known = Set(services.map(\.serviceName))
            for name in requested where !known.contains(name) {
                print("Warning: No such service: \(name)")
            }
        }

        let containers = services.map { serviceName, service in
            ComposeProject.ServiceTarget(
                serviceName: serviceName,
                service: service,
                containerName: ComposeProject.containerName(
                    serviceName: serviceName, service: service, projectName: projectName)
            )
        }
        return ComposeProject(compose: compose, projectName: projectName, services: containers, cwd: cwd)
    }
}

/// A resolved compose project: the decoded file, its project name, and its
/// services (in dependency order) paired with their container names.
public struct ComposeProject {
    public let compose: DockerCompose
    public let projectName: String
    public let services: [ServiceTarget]
    public let cwd: String

    /// A service paired with the container name it maps to.
    public struct ServiceTarget {
        public let serviceName: String
        public let service: Service
        public let containerName: String
    }

    /// Container name for a service: explicit `container_name` if set, else the
    /// `"<project>-<service>"` convention used across the tool.
    public static func containerName(serviceName: String, service: Service, projectName: String) -> String {
        service.container_name ?? "\(projectName)-\(serviceName)"
    }
}
