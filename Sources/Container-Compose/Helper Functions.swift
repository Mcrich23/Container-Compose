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
//  Helper Functions.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//

import Foundation
import Yams
import Rainbow
import ContainerCommands
import ContainerAPIClient

public func resolvedPath(for path: String, relativeTo baseURL: URL) -> String {
    let expandedPath = NSString(string: path).expandingTildeInPath
    return URL(fileURLWithPath: expandedPath, relativeTo: baseURL).standardizedFileURL.path
}


/// The standard executable directories appended as a fallback when building the
/// PATH for spawned `container` processes.
public let standardExecutablePathFallback = [
    "/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
]

/// Builds the PATH used for spawned child processes by preserving the user's
/// inherited PATH and appending any standard fallback directories that are not
/// already present. This keeps `container` binaries installed outside the
/// standard locations (e.g. Nix at `/run/current-system/sw/bin`) reachable while
/// still guaranteeing the common Homebrew/system directories are available.
/// - Parameters:
///   - existing: The inherited PATH value (typically `$PATH`), or `nil` if unset.
///   - fallback: The standard directories to ensure are present.
/// - Returns: A `:`-separated PATH string preserving the user's order, followed
///   by any missing fallback directories.
public func mergedExecutablePath(
    existing: String?,
    fallback: [String] = standardExecutablePathFallback
) -> String {
    let existingEntries = (existing ?? "")
        .split(separator: ":", omittingEmptySubsequences: true)
        .map(String.init)

    var seen = Set(existingEntries)
    var merged = existingEntries

    for dir in fallback where !seen.contains(dir) {
        merged.append(dir)
        seen.insert(dir)
    }

    return merged.joined(separator: ":")
}

/// Loads environment variables from a .env file.
/// - Parameter path: The full path to the .env file.
/// - Returns: A dictionary of key-value pairs representing environment variables.
public func loadEnvFile(path: String) -> [String: String] {
    var envVars: [String: String] = [:]
    let fileURL = URL(fileURLWithPath: path)
    do {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.split(separator: "\n")
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Ignore empty lines and comments
            if !trimmedLine.isEmpty && !trimmedLine.starts(with: "#") {
                // Parse key=value pairs
                if let eqIndex = trimmedLine.firstIndex(of: "=") {
                    let key = String(trimmedLine[..<eqIndex])
                    let value = String(trimmedLine[trimmedLine.index(after: eqIndex)...])
                    envVars[key] = value
                }
            }
        }
    } catch {
        // print("Warning: Could not read .env file at \(path): \(error.localizedDescription)")
        // Suppress error message if .env file is optional or missing
    }
    return envVars
}

/// Resolves environment variables within a string (e.g., ${VAR:-default}, ${VAR:?error}).
/// Supports Compose defaults, required values, alternatives and escaped dollars.
/// Missing variables produce a warning and an empty string.
/// - Parameters:
///   - value: The string possibly containing environment variable references.
///   - envVars: A dictionary of environment variables to use for resolution.
/// - Returns: The string with all recognized environment variables resolved.
public func resolveVariable(_ value: String, with envVars: [String: String]) -> String {
    let combined = envVars.merging(ProcessInfo.processInfo.environment) { _, process in process }
    do {
        return try ComposeInterpolation(environment: combined).expand(value)
    } catch {
        Application.exit(withError: error)
    }
}

/// Assembles container variables from service files and explicit values.
/// The interpolation environment supplies substitutions without being injected.
/// - Important: Pass `interpolate: false` for values already expanded by project loading.
func assembleServiceEnvironment(
    service: Service,
    composeDirectory: String,
    interpolationEnvironment: [String: String],
    interpolate: Bool = true
) -> [String: String] {
    var result: [String: String] = [:]
    for path in service.env_file ?? [] {
        let fullPath = resolvedPath(for: path, relativeTo: URL(fileURLWithPath: composeDirectory, isDirectory: true))
        result.merge(loadEnvFile(path: fullPath)) { _, later in later }
    }
    for (key, value) in service.environment ?? [:] {
        result[key] = interpolate ? resolveVariable(value, with: interpolationEnvironment) : value
    }
    return result
}

/// Derives a project name from the current working directory. It replaces any '.' characters with
/// '_' to ensure compatibility with container naming conventions.
///
/// - Parameter cwd: The current working directory path.
/// - Returns: A sanitized project name suitable for container naming.
public func deriveProjectName(cwd: String) -> String {
    // We need to replace '.' with _ because it is not supported in the container name
    let projectName = URL(fileURLWithPath: cwd).lastPathComponent.replacingOccurrences(of: ".", with: "_")
    return projectName
}

/// Resolves the project name using the same precedence as Docker Compose:
/// 1. The `-p`/`--project-name` flag, 2. the `COMPOSE_PROJECT_NAME` environment variable
/// (process environment takes precedence over the .env file), 3. the top-level `name` field
/// from the compose file (with variable interpolation), 4. the working directory name.
///
/// - Parameters:
///   - flagValue: The value of the `-p`/`--project-name` flag, if provided.
///   - composeName: The top-level `name` field from the compose file, if present.
///   - envVars: Environment variables loaded from the .env file.
///   - projectDirectory: Directory whose name is the fallback project name.
///     Pass the compose file's directory, not the process cwd: the name must
///     come out the same no matter where the command is run from, or
///     `up -f <path>` and `stop -f <path>` from different directories would
///     target different projects.
///   - processEnv: The process environment (injectable for testing).
/// - Returns: The resolved project name.
public func resolveProjectName(
    flagValue: String?,
    composeName: String?,
    envVars: [String: String],
    projectDirectory: String,
    processEnv: [String: String] = ProcessInfo.processInfo.environment
) -> String {
    if let flagValue, !flagValue.isEmpty {
        return flagValue
    }
    let combinedEnv = processEnv.merging(envVars) { (current, _) in current }
    if let envName = combinedEnv["COMPOSE_PROJECT_NAME"], !envName.isEmpty {
        return envName
    }
    if let composeName {
        return resolveVariable(composeName, with: envVars)
    }
    return deriveProjectName(cwd: projectDirectory)
}

/// Converts Docker Compose port specification into a container run -p format.
/// Handles various formats: "PORT", "HOST:PORT", "IP:HOST:PORT", and optional protocol.
/// - Parameter portSpec: The port specification string from docker-compose.yml.
/// - Returns: A properly formatted port binding for `container run -p`.
public func composePortToRunArg(_ portSpec: String) -> String {
    // Check for protocol suffix (e.g., "/tcp" or "/udp")
    var protocolSuffix = ""
    var portBody = portSpec
    if let slashRange = portSpec.range(of: "/", options: [.backwards]) {
        let afterSlash = portSpec[slashRange.lowerBound...]
        let protocolPart = String(afterSlash)
        if protocolPart == "/tcp" || protocolPart == "/udp" {
            protocolSuffix = protocolPart
            portBody = String(portSpec[..<slashRange.lowerBound])
        }
    }

    let components = portBody.split(separator: ":", maxSplits: 3).map(String.init)
    switch components.count {
    case 1:
        let containerPort = components[0]
        return "0.0.0.0:\(containerPort):\(containerPort)\(protocolSuffix)"
    case 2:
        let hostPart = components[0]
        let containerPart = components[1]
        let hasIPv4 = hostPart.contains(".")
        let hasIPv6 = hostPart.contains(":") && hostPart.hasPrefix("[") && hostPart.hasSuffix("]")
        if hasIPv4 || hasIPv6 {
            return "\(hostPart):\(containerPart)\(protocolSuffix)"
        } else {
            return "0.0.0.0:\(hostPart):\(containerPart)\(protocolSuffix)"
        }
    case 3:
        let ipPart = components[0]
        let hostPart = components[1]
        let containerPart = components[2]
        return "\(ipPart):\(hostPart):\(containerPart)\(protocolSuffix)"
    default:
        return portSpec
    }
}

/// Converts a Docker Compose `volumes:` entry into the `--volume` arguments for `container run`.
/// - Important: Pass `interpolate: false` for values already expanded by project loading.
func composeVolumeToRunArgs(
    _ volume: String,
    composeDirectory: String,
    fileManager: FileManager = .default,
    environmentVariables: [String: String] = [:],
    projectName: String?,
    volumeDefinitions: [String: Volume?]? = nil,
    interpolate: Bool = true
) throws -> [String] {
    let resolvedVolume = interpolate ? resolveVariable(volume, with: environmentVariables) : volume
    var args: [String] = []

    let components = resolvedVolume.split(separator: ":", maxSplits: 2).map(String.init)
    guard components.count >= 2 else {
        print("Warning: Volume entry '\(resolvedVolume)' has an invalid format (expected 'source:destination'). Skipping.")
        return []
    }

    let source = components[0]
    let destination = components[1]
    let mode = components.count == 3 ? components[2] : nil

    func bindMountArg(source: String) -> String {
        if let mode { return "\(source):\(destination):\(mode)" }
        return "\(source):\(destination)"
    }

    if source.contains("/") || source.starts(with: ".") || source.starts(with: "..") {
        let fullHostPath = resolvedPath(for: source, relativeTo: URL(fileURLWithPath: composeDirectory, isDirectory: true))

        if fileManager.fileExists(atPath: fullHostPath) {
            args.append("-v")
            args.append(bindMountArg(source: fullHostPath))
        } else {
            do {
                try fileManager.createDirectory(atPath: fullHostPath, withIntermediateDirectories: true, attributes: nil)
                print("Info: Created missing host directory for volume: \(fullHostPath)")
                args.append("-v")
                args.append(bindMountArg(source: fullHostPath))
            } catch {
                print("Error: Could not create host directory '\(fullHostPath)' for volume '\(resolvedVolume)': \(error.localizedDescription). Skipping this volume.")
            }
        }
    } else {
        let volumeDefinition = volumeDefinitions?[source] ?? nil
        let actualVolumeName = composeNamedVolumeName(
            source: source,
            projectName: projectName,
            volumeDefinition: volumeDefinition
        )

        args.append("-v")
        args.append(bindMountArg(source: actualVolumeName))
    }

    return args
}

func composeNamedVolumeName(
    source: String,
    projectName: String?,
    volumeDefinition: Volume?
) -> String {
    if let explicitName = volumeDefinition?.name {
        return explicitName
    }

    if volumeDefinition?.external?.isExternal == true {
        return volumeDefinition?.external?.name ?? source
    }

    guard let projectName, !projectName.isEmpty else {
        return source
    }

    return "\(projectName)_\(source)"
}

extension String: @retroactive Error {}

/// A structure representing the result of a command-line process execution.
public struct CommandResult {
    /// The standard output captured from the process.
    public let stdout: String

    /// The standard error output captured from the process.
    public let stderr: String

    /// The exit code returned by the process upon termination.
    public let exitCode: Int32
}

extension NamedColor: @retroactive Codable {

}

extension Flags.Logging {
    /// Generates an array of flags that allow us to pass down Logging options
    func passThroughCommands() -> [String] {
        var flags: [String] = []
        
        if debug {
            flags.append("--debug")
        }
        
        return flags
    }
}

/// Runs a command, streaming stdout and stderr chunks as they arrive.
///
/// - Note: `ComposeUp.streamCommand` duplicates this; merge them once open
///   PRs reworking `ComposeUp` land.
/// - Parameters:
///   - command: The name of the command to run (e.g., `"container"`).
///   - args: Command-line arguments to pass to the command.
///   - cwd: The working directory to launch the process in.
///   - onStdout: Closure called with streamed stdout chunks.
///   - onStderr: Closure called with streamed stderr chunks.
/// - Returns: The process's exit code.
/// - Throws: If the process fails to launch.
@discardableResult
public func streamSubprocess(
    _ command: String,
    args: [String] = [],
    cwd: String,
    onStdout: @escaping (@Sendable (String) -> Void),
    onStderr: @escaping (@Sendable (String) -> Void)
) async throws -> Int32 {
    try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.environment = ProcessInfo.processInfo.environment.merging([
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]) { _, new in new }

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let string = String(data: data, encoding: .utf8) {
                onStdout(string)
            }
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let string = String(data: data, encoding: .utf8) {
                onStderr(string)
            }
        }

        process.terminationHandler = { proc in
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            continuation.resume(returning: proc.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
