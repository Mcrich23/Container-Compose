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
import ContainerAPIClient
import ContainerCommands
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
    private static let supportedComposeFilenames = [
        "compose.yml",
        "compose.yaml",
        "docker-compose.yml",
        "docker-compose.yaml",
    ]

    private var fileManager: FileManager { .default }

    /// Working directory the command runs in (`--cwd`, else the process cwd).
    public var cwd: String { process.cwd ?? fileManager.currentDirectoryPath }

    var cwdURL: URL { URL(fileURLWithPath: cwd) }

    /// Absolute paths to the compose files to load, in order: every explicit
    /// `--file` if any were given, otherwise the first supported filename found
    /// in `cwd` (or the default name, so callers get a consistent "not found"
    /// error). Multiple files are deep-merged by `loadCompose()`.
    public var composePaths: [String] {
        if !composeFileOptions.composeFilenames.isEmpty {
            return composeFileOptions.composeFilenames.map { resolvedPath(for: $0, relativeTo: cwdURL) }
        }

        for filename in Self.supportedComposeFilenames {
            let candidate = cwdURL.appending(path: filename).path
            if fileManager.fileExists(atPath: candidate) {
                return [candidate]
            }
        }

        return [cwdURL.appending(path: Self.supportedComposeFilenames[0]).path]
    }

    /// The primary compose file (first `-f`, or the discovered default). Used for
    /// the base directory of relative paths and for "not found" messages.
    public var composePath: String { composePaths[0] }

    /// Directory containing the primary compose file (the base for relative
    /// `context`, `env_file`, etc.). Per the Compose spec, relative paths are
    /// resolved against the first file's directory even when merging.
    public var composeDirectory: String {
        URL(fileURLWithPath: composePath).deletingLastPathComponent().path
    }

    /// Path to the environment file: the first `--env-file` if given, otherwise
    /// `.env` in `cwd`.
    public var envFilePath: String {
        let envFile = process.envFile.first ?? ".env"
        return resolvedPath(for: envFile, relativeTo: cwdURL)
    }

    /// Reads the compose file(s), deep-merges them in order (later files win;
    /// see `mergeYAML`), and expands YAML values before decoding.
    /// Commands receive resolved values and must not interpolate them again.
    /// - Throws: `YamlError.composeFileNotFound` if any file is missing.
    public func loadCompose() throws -> DockerCompose {
        var merged: Node?
        for path in composePaths {
            guard let data = fileManager.contents(atPath: path),
                  let yaml = String(data: data, encoding: .utf8)
            else {
                throw YamlError.composeFileNotFound(URL(fileURLWithPath: path).deletingLastPathComponent().path)
            }
            // An empty override file parses to nil; skip it.
            guard let node = try Yams.compose(yaml: yaml) else { continue }
            merged = merged.map { Self.mergeYAML($0, node) } ?? node
        }
        guard let merged else {
            throw YamlError.composeFileNotFound(composeDirectory)
        }
        let environment = loadEnvFile(path: envFilePath).merging(ProcessInfo.processInfo.environment) { _, process in process }
        let expanded = try ComposeInterpolation(environment: environment).expandValues(in: merged)
        return try YAMLDecoder().decode(DockerCompose.self, from: expanded)
    }

    /// Deep-merges two compose documents: mappings merge key by key; scalars
    /// and sequences are replaced by `override`.
    static func mergeYAML(_ base: Node, _ override: Node) -> Node {
        guard case .mapping(let baseMap) = base, case .mapping(let overrideMap) = override else {
            return override
        }
        var result = baseMap
        for (key, overrideValue) in overrideMap {
            if let baseValue = result[key] {
                result[key] = mergeYAML(baseValue, overrideValue)
            } else {
                result[key] = overrideValue
            }
        }
        return .mapping(result)
    }

    /// Project name used to namespace containers, resolved with the same
    /// precedence as docker compose: the `-p`/`--project-name` flag, then
    /// `COMPOSE_PROJECT_NAME` (process environment over the .env file), then
    /// the compose `name:` field (with `${VAR:-default}` interpolation), then
    /// the sanitized working-directory name.
    public func projectName(for compose: DockerCompose) -> String {
        resolveProjectName(
            flagValue: composeFileOptions.projectName,
            composeName: compose.name,
            envVars: loadEnvFile(path: envFilePath),
            projectDirectory: composeDirectory)
    }

    /// Resolves the services the command should act on, in dependency
    /// (topological) order.
    ///
    /// Selection delegates to `Service.selectServices` — the algorithm
    /// `up`/`build`/`down` share since #126 — so Compose `profiles` gating and
    /// dependency expansion behave identically here: with `requested` empty,
    /// every profile-eligible service plus its dependencies; otherwise the
    /// requested services plus their transitive dependencies (which bypass the
    /// profile gate).
    ///
    /// Note: callers that want a hard error on unknown service names (e.g.
    /// `ComposeUp`) should call `Service.validateRequestedServices` before
    /// or after `resolve()`.
    ///
    /// - Parameter requested: Explicitly requested service names; empty means
    ///   the project's default selection.
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
        return Service.selectServices(
            from: services,
            requestedServices: requested,
            activeProfiles: composeFileOptions.activeProfiles)
    }

    /// One-shot convenience: load the compose file and resolve everything a
    /// command typically needs.
    ///
    /// - Parameter requested: Explicitly requested service names; empty means
    ///   the project's default selection.
    public func resolve(filteringBy requested: [String] = []) throws -> ComposeProject {
        let compose = try loadCompose()
        let projectName = projectName(for: compose)
        let services = try orderedServices(of: compose, filteringBy: requested)

        let containers = services.map { serviceName, service in
            ComposeProject.ServiceTarget(
                serviceName: serviceName,
                service: service,
                candidateContainerNames: ComposeProject.candidateContainerNames(
                    serviceName: serviceName, service: service, projectName: projectName)
            )
        }
        return ComposeProject(compose: compose, projectName: projectName, services: containers)
    }
}

/// A resolved compose project: the decoded file, its project name, and its
/// services (in dependency order) paired with their container names.
public struct ComposeProject {
    public let compose: DockerCompose
    public let projectName: String
    public let services: [ServiceTarget]

    /// A service paired with the container names it may map to.
    public struct ServiceTarget {
        public let serviceName: String
        public let service: Service
        /// Names the service's container may exist under, in the order they
        /// should be tried (see `candidateContainerNames(serviceName:service:projectName:)`).
        public let candidateContainerNames: [String]

        /// Reports whether a container is this service's container within
        /// `projectName`.
        ///
        /// A labeled container matches solely by its
        /// `com.docker.compose.project` and `.service` labels; the
        /// candidate-name fallback applies only to unlabeled containers from
        /// before the labels existed.
        ///
        /// - Returns: `true` when the labels name `projectName` and this
        ///   service, or when the container is unlabeled and `containerID` is
        ///   one of the candidate names.
        /// - Note: See ``ComposeProject/ownsContainer`` for the ownership rule
        ///   this builds on.
        func matches(containerID: String, labels: [String: String], projectName: String) -> Bool {
            guard ComposeProject.ownsContainer(labels: labels, projectName: projectName) else { return false }
            if labels["com.docker.compose.project"] != nil {
                return labels["com.docker.compose.service"] == serviceName
            }
            return candidateContainerNames.contains(containerID)
        }
    }

    /// Container names a service's container may exist under, in try order.
    ///
    /// There is no single authoritative name: `up` names containers
    /// `<service>.<dnsDomain>` when the project's DNS domain is registered with
    /// `container system dns` at creation time (#97), `<project>-<service>`
    /// otherwise, and an explicit `container_name` overrides both — so a
    /// container from a previous run may exist under any of the three.
    /// Commands that only need running containers of the project can instead
    /// match the `com.docker.compose.project`/`.service` labels stamped since
    /// #126, but names remain necessary for containers created before that.
    public static func candidateContainerNames(serviceName: String, service: Service, projectName: String) -> [String] {
        var candidates = ["\(projectName)-\(serviceName)"]
        if let dnsDomain = sanitizeDnsDomain(projectName) {
            candidates.append("\(serviceName).\(dnsDomain)")
        }
        if let explicit = service.container_name, !candidates.contains(explicit) {
            // First, not last: an explicit name is what `up` actually uses, so
            // it's the most likely to exist.
            candidates.insert(explicit, at: 0)
        }
        return candidates
    }

    /// Reports whether a container belongs to `projectName`, so compose
    /// commands know they may list, stop, or remove it.
    ///
    /// A labeled container belongs to whatever project its
    /// `com.docker.compose.project` label names, regardless of its name.
    /// An unlabeled container is treated as belonging to the project: a
    /// matching candidate name is the only identity it has.
    ///
    /// - Returns: `true` when the labels name `projectName` or carry no
    ///   project label; `false` when they name a different project.
    /// - Important: Candidate names can collide across projects (project
    ///   `demo` + service `web-x` produce `demo-web-x`, which is also the
    ///   name project `demo-web` gives its service `x`). A collision must
    ///   not let one project act on another's container.
    static func ownsContainer(labels: [String: String], projectName: String) -> Bool {
        guard let labeledProject = labels["com.docker.compose.project"] else { return true }
        return labeledProject == projectName
    }

    /// Coerce an arbitrary project name into a single DNS label: lowercase, only
    /// `[a-z0-9-]`, no leading/trailing/repeated hyphens, max 63 chars. Returns
    /// `nil` when nothing usable remains (e.g. a name made entirely of separators).
    static func sanitizeDnsDomain(_ name: String) -> String? {
        let allowed: Set<Character> = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        var out = ""
        for ch in name.lowercased() {
            out.append(allowed.contains(ch) ? ch : "-")
        }
        while out.contains("--") {
            out = out.replacingOccurrences(of: "--", with: "-")
        }
        while out.hasPrefix("-") { out.removeFirst() }
        while out.hasSuffix("-") { out.removeLast() }
        if out.count > 63 {
            out = String(out.prefix(63))
            while out.hasSuffix("-") { out.removeLast() }
        }
        return out.isEmpty ? nil : out
    }
}
