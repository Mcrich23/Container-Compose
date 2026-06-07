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
//  ComposeExec.swift
//  Container-Compose
//
//  Implements `exec SERVICE COMMAND [ARG...]`, mirroring `docker compose exec`:
//  resolve a single service to its container name and run a command inside it.
//

import ArgumentParser
import ContainerCommands
import ContainerAPIClient
import Foundation
import Yams

public struct ComposeExec: AsyncParsableCommand {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "exec",
        abstract: "Execute a command in a running service container",
        discussion: """
        Runs COMMAND (with any ARGs) inside the running container for SERVICE, \
        like `docker compose exec`. The command is launched with the terminal's \
        standard input/output/error inherited, so interactive shells work \
        (e.g. `exec -it web sh`).

        Note: replicas are not supported, so `--index` is accepted only for CLI \
        parity with `docker compose exec` and is a no-op.
        """
    )

    @OptionGroup
    var project: ComposeProjectOptions

    @OptionGroup
    var logging: Flags.Logging

    /// Accepted for `docker compose exec` parity. Replicas aren't supported, so
    /// there is only ever one container per service; this value is ignored.
    @Option(name: .long, help: "Index of the container if service has multiple replicas (no-op; unsupported)")
    var index: Int = 1

    @Argument(help: "The service whose container the command runs in")
    var service: String

    @Argument(
        parsing: .captureForPassthrough,
        help: "The command (and any arguments) to execute inside the container"
    )
    var command: [String]

    public mutating func run() async throws {
        guard !command.isEmpty else {
            throw ValidationError("No command was provided to exec.")
        }

        // Resolve the single requested service, failing fast on an unknown
        // name with the noSuchService contract #139 established for `up`.
        let resolved = try project.resolve(filteringBy: [service])
        let defined: [(serviceName: String, service: Service)] = resolved.compose.services.compactMap { name, svc in
            svc.map { (name, $0) }
        }
        try Service.validateRequestedServices([service], against: defined)
        guard let target = resolved.services.first(where: { $0.serviceName == service }) else {
            throw ComposeError.noSuchService(service)
        }

        // Find the service's container via the shared matching rule: labels
        // are authoritative, candidate names identify only unlabeled
        // pre-label containers.
        let client = ContainerClient()
        let snapshots = (try? await client.list()) ?? []
        let container = snapshots.first { snapshot in
            target.matches(containerID: snapshot.id, labels: snapshot.configuration.labels, projectName: resolved.projectName)
        }
        guard let container else {
            throw ComposeExecError.containerNotFound(service: service, container: target.candidateContainerNames.joined(separator: ", "))
        }
        guard container.status == .running else {
            throw ComposeExecError.containerNotRunning(service: service, container: container.id)
        }
        let containerName = container.id

        // Build the `container exec` argument list, mapping our compose-level
        // process flags onto the flags `container exec` understands.
        var execArgs: [String] = ["exec"]

        if project.process.interactive {
            execArgs.append("--interactive")
        }
        if project.process.tty {
            execArgs.append("--tty")
        }
        if let user = project.process.user {
            execArgs.append(contentsOf: ["--user", user])
        }
        if let workdir = project.process.cwd {
            execArgs.append(contentsOf: ["--workdir", workdir])
        }
        for env in project.process.env {
            execArgs.append(contentsOf: ["--env", env])
        }
        for envFile in project.process.envFile {
            execArgs.append(contentsOf: ["--env-file", envFile])
        }

        execArgs.append(contentsOf: logging.passThroughCommands())
        execArgs.append(containerName)
        execArgs.append(contentsOf: command)

        // Shell out to the `container` CLI with the terminal's stdio inherited.
        //
        // We do NOT reuse ComposeUp's `streamCommand`, which captures stdout/stderr
        // through pipes — that breaks interactive sessions (no TTY, no live stdin).
        // Inheriting FileHandle.standardInput/Output/Error gives the child a real
        // terminal, so `exec -it web sh` behaves like `docker compose exec`.
        let exitCode = try runInheritingTerminal("container", args: execArgs)
        if exitCode != 0 {
            throw ExitCode(exitCode)
        }
    }

    /// Runs a command with the parent process's stdin/stdout/stderr inherited and
    /// blocks until it exits, returning its exit status.
    private func runInheritingTerminal(_ command: String, args: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args
        process.currentDirectoryURL = URL(fileURLWithPath: project.cwd)
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]) { _, new in new }

        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

enum ComposeExecError: Error, CustomStringConvertible {
    case containerNotFound(service: String, container: String)
    case containerNotRunning(service: String, container: String)

    var description: String {
        switch self {
        case .containerNotFound(let service, let container):
            return "Container for service '\(service)' (\(container)) not found. Is it running? Try `container-compose up`."
        case .containerNotRunning(let service, let container):
            return "Container for service '\(service)' (\(container)) is not running. Start it with `container-compose up`."
        }
    }
}
