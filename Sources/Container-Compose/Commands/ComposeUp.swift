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
//  ComposeUp.swift
//  Container-Compose
//
//  Created by Morris Richman on 6/19/25.
//

import ArgumentParser
import ContainerCommands
import ContainerAPIClient
import ContainerizationExtras
import Foundation
@preconcurrency import Rainbow
import Yams

private enum ServiceStartState: Codable, Equatable {
    case running
    case completed
}

public struct ComposeUp: AsyncParsableCommand, @unchecked Sendable {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "up",
        abstract: "Start containers with compose"
    )

    @Argument(help: "Specify the services to start")
    var services: [String] = []

    @Flag(
        name: [.customShort("d"), .customLong("detach")],
        help: "Detaches from container logs. Note: If you do NOT detach, killing this process will NOT kill the container. To kill the container, run container-compose down")
    var detach: Bool = false

    @OptionGroup
    var composeFileOptions: ComposeFileOptions

    private static let supportedComposeFilenames = [
        "compose.yml",
        "compose.yaml",
        "docker-compose.yml",
        "docker-compose.yaml",
    ]

    private var cwdURL: URL {
        URL(fileURLWithPath: cwd)
    }

    private var composePath: String {
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

    private var envFilePath: String {
        let envFile = process.envFile.first ?? ".env"
        return resolvedPath(for: envFile, relativeTo: cwdURL)
    }

    private var composeDirectory: String {
        URL(fileURLWithPath: composePath).deletingLastPathComponent().path
    }

    @Flag(name: [.customShort("b"), .customLong("build")])
    var rebuild: Bool = false

    @Flag(name: .long, help: "Do not use cache")
    var noCache: Bool = false

    @OptionGroup
    var process: Flags.Process

    @OptionGroup
    var logging: Flags.Logging

    private var cwd: String { process.cwd ?? FileManager.default.currentDirectoryPath }

    private var fileManager: FileManager { FileManager.default }
    private var projectName: String?
    private var environmentVariables: [String: String] = [:]
    private var containerIps: [String: String] = [:]
    private var serviceStartStates: [String: ServiceStartState] = [:]
    private var serviceHealth: [String: Bool] = [:]
    private var containerConsoleColors: [String: NamedColor] = [:]

    private static let availableContainerConsoleColors: Set<NamedColor> = [
        .blue, .cyan, .magenta, .lightBlack, .lightBlue, .lightCyan, .lightYellow, .yellow, .lightGreen, .green,
    ]

    public mutating func run() async throws {
        // Read compose.yml content
        guard let yamlData = fileManager.contents(atPath: composePath) else {
            let path = URL(fileURLWithPath: composePath)
                .deletingLastPathComponent()
                .path
            throw YamlError.composeFileNotFound(path)
        }

        // Decode the YAML file into the DockerCompose struct
        let dockerComposeString = String(data: yamlData, encoding: .utf8)!
        let dockerCompose = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)

        // Load environment variables from .env file
        environmentVariables = loadEnvFile(path: envFilePath)

        // Handle 'version' field
        if let version = dockerCompose.version {
            print("Info: Docker Compose file version parsed as: \(version)")
            print("Note: The 'version' field influences how a Docker Compose CLI interprets the file, but this custom 'container-compose' tool directly interprets the schema.")
        }

        // Determine project name for container naming
        if let name = dockerCompose.name {
            projectName = name
            print("Info: Docker Compose project name parsed as: \(name)")
            print(
                "Note: The 'name' field currently only affects container naming (e.g., '\(name)-serviceName'). Full project-level isolation for other resources (networks, implicit volumes) is not implemented by this tool."
            )
        } else {
            projectName = deriveProjectName(cwd: cwd)
            print("Info: No 'name' field found in docker-compose.yml. Using directory name as project name: \(projectName ?? "")")
        }

        // Get Services to use
        var services: [(serviceName: String, service: Service)] = dockerCompose.services.compactMap({ serviceName, service in
            guard let service else { return nil }
            return (serviceName, service)
        })
        services = try Service.topoSortConfiguredServices(services)

        // Filter for specified services
        if !self.services.isEmpty {
            services = services.filter({ serviceName, service in
                self.services.contains(where: { $0 == serviceName }) || self.services.contains(where: { service.dependedBy.contains($0) })
            })
        }

        // Stop Services
        try await stopOldStuff(services.map({ $0.serviceName }), remove: true)

        // Process top-level networks
        // This creates named networks defined in the docker-compose.yml
        if let networks = dockerCompose.networks {
            print("\n--- Processing Networks ---")
            for (networkName, networkConfig) in networks {
                try await setupNetwork(name: networkName, config: networkConfig)
            }
            print("--- Networks Processed ---\n")
        }

        // Process top-level volumes
        // This creates named volumes defined in the docker-compose.yml
        if let volumes = dockerCompose.volumes {
            print("\n--- Processing Volumes ---")
            for (volumeName, volumeConfig) in volumes {
                guard let volumeConfig else { continue }
                try await createVolume(name: volumeName, config: volumeConfig)
            }
            print("--- Volumes Processed ---\n")
        }

        // Process each service defined in the docker-compose.yml
        print("\n--- Processing Services ---")

        print(services.map(\.serviceName))
        for (serviceName, service) in services {
            try await configService(service, serviceName: serviceName, from: dockerCompose)
        }

        if !detach {
            await waitForever()
        }
    }

    func waitForever() async -> Never {
        // `AsyncStream<Void>(unfolding: () async -> Void?)` ends only when the
        // closure returns `nil`. An empty closure returns `()`, which Swift
        // auto-wraps as `.some(())` — never `nil` — so the previous
        // `for await _ in AsyncStream<Void>(unfolding: {})` produced an
        // infinite stream of `Void` values with no `await` between them and
        // pinned a CPU core at 100% (issue #27).
        //
        // Suspending on a continuation that is never resumed parks the task
        // indefinitely with zero CPU. `withUnsafeContinuation` (rather than
        // `withCheckedContinuation`) avoids the runtime's "continuation leaked"
        // diagnostic — leaking is the intent here, since the contract is to
        // wait until the process is killed.
        await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
        fatalError("unreachable")
    }

    /// Translates Compose's `entrypoint` + `command` into args for `container run`.
    ///
    /// Compose semantics:
    ///   - `entrypoint` (when set) replaces the image's ENTRYPOINT.
    ///   - `command` (when set) replaces the image's CMD and is passed to the
    ///     resolved entrypoint as its argv tail.
    ///   - Both can be set together; they are NOT mutually exclusive.
    ///
    /// Mapping to `container run`:
    ///   - First element of `entrypoint` → `--entrypoint <bin>` flag (must
    ///     precede the image — `container run` only accepts a single executable
    ///     for `--entrypoint`, not a full argv).
    ///   - Remaining `entrypoint` elements + every `command` element → positional
    ///     args after the image.
    ///
    /// Notable case from issue #77: `entrypoint: ["/bin/bash", "-c"]` +
    /// `command: ["<multi-line script>"]` becomes
    /// `--entrypoint /bin/bash <image> -c <script>`, so bash receives both its
    /// `-c` flag and the script as a single argument.
    static func entrypointAndCommandArgs(
        entrypoint: [String]?,
        command: [String]?
    ) -> (entrypointFlag: String?, positional: [String]) {
        var positional: [String] = []
        let entrypointFlag: String?
        if let entrypoint, !entrypoint.isEmpty {
            entrypointFlag = entrypoint.first
            positional.append(contentsOf: entrypoint.dropFirst())
        } else {
            entrypointFlag = nil
        }
        if let command {
            positional.append(contentsOf: command)
        }
        return (entrypointFlag, positional)
    }

    static func hostnameRunArgs(
        hostname: String?,
        serviceName: String,
        environmentVariables: [String: String]
    ) -> (args: [String], warning: String?) {
        guard let hostname else {
            return ([], nil)
        }

        let resolvedHostname = resolveVariable(hostname, with: environmentVariables)
        return (
            [],
            "Warning: Service '\(serviceName)' defines hostname '\(resolvedHostname)', but Apple Container does not currently expose a container run hostname flag."
        )
    }

    private func getIPForRunningService(_ serviceName: String) async throws -> String? {
        guard let projectName else { return nil }

        let containerName = "\(projectName)-\(serviceName)"

        let client = ContainerClient()
        let container = try await client.get(id: containerName)
        // Use the container's own address, not the network gateway — every
        // container on a network shares the same gateway, so substituting the
        // gateway broke service-name -> IP environment resolution.
        let ip = container.networks.compactMap { $0.ipv4Address.address.description }.first

        return ip
    }

    /// Repeatedly checks `container list -a` until the given container is listed as `running` or `stopped`.
    /// - Parameters:
    ///   - containerName: The exact name of the container (e.g. "Assignment-Manager-API-db").
    ///   - timeout: Max seconds to wait before failing.
    ///   - interval: How often to poll (in seconds).
    private func waitUntilServiceStarted(_ serviceName: String, timeout: TimeInterval = 30, interval: TimeInterval = 0.5) async throws -> ServiceStartState {
        guard let projectName else { throw ComposeError.invalidProjectName }
        let containerName = "\(projectName)-\(serviceName)"

        let deadline = Date().addingTimeInterval(timeout)
        let client = ContainerClient()

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            let container = try? await client.get(id: containerName)
            if container?.status == .running {
                return .running
            }
            if container?.status == .stopped {
                return .completed
            }
        }

        throw NSError(
            domain: "ContainerWait", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Timed out waiting for container '\(containerName)' to start."
            ])
    }

    private func stopOldStuff(_ services: [String], remove: Bool) async throws {
        guard let projectName else { return }
        let containers = services.map { "\(projectName)-\($0)" }

        for container in containers {
            print("Stopping container: \(container)")
            let client = ContainerClient()
            guard let container = try? await client.get(id: container) else { continue }

            do {
                try await client.stop(id: container.id)
            } catch {
                print("Error Stopping Container: \(error)")
            }
            if remove {
                do {
                    try await client.delete(id: container.id)
                } catch {
                    print("Error Removing Container: \(error)")
                }
            }
        }
    }

    // MARK: Compose Top Level Functions

    private mutating func updateEnvironmentWithServiceIP(_ serviceName: String) async throws {
        let ip = try await getIPForRunningService(serviceName)
        self.containerIps[serviceName] = ip
        for (key, value) in environmentVariables.map({ ($0, $1) }) where value == serviceName {
            self.environmentVariables[key] = ip ?? value
        }
    }

    private func createVolume(name volumeName: String, config volumeConfig: Volume) async throws {
        let actualVolumeName = volumeConfig.name ?? volumeConfig.external?.name ?? volumeName

        if volumeConfig.external?.isExternal == true {
            print("Info: Volume '\(volumeName)' is declared as external.")
            print("This tool assumes external volume '\(actualVolumeName)' already exists and will not attempt to create it.")
            return
        }

        if (try? await ClientVolume.inspect(actualVolumeName)) != nil {
            print("Volume '\(actualVolumeName)' already exists")
            return
        }

        print("Creating volume: \(volumeName) (Actual name: \(actualVolumeName))")
        _ = try await ClientVolume.create(
            name: actualVolumeName,
            driver: volumeConfig.driver ?? "local",
            driverOpts: volumeConfig.driver_opts ?? [:],
            labels: volumeConfig.labels ?? [:]
        )
        print("Volume '\(actualVolumeName)' created")
    }

    private func setupNetwork(name networkName: String, config networkConfig: Network?) async throws {
        let actualNetworkName = networkConfig?.name ?? networkName  // Use explicit name or key as name

        if let externalNetwork = networkConfig?.external, externalNetwork.isExternal {
            print("Info: Network '\(networkName)' is declared as external.")
            print("This tool assumes external network '\(externalNetwork.name ?? actualNetworkName)' already exists and will not attempt to create it.")
        } else {
            let networkCreateArgs: [String] = ["network", "create"]

            #warning("Docker Compose Network Options Not Supported")
            // Add driver and driver options
            if let driver = networkConfig?.driver, !driver.isEmpty {
                //                    networkCreateArgs.append("--driver")
                //                    networkCreateArgs.append(driver)
                print("Network Driver Detected, But Not Supported")
            }
            if let driverOpts = networkConfig?.driver_opts, !driverOpts.isEmpty {
                //                    for (optKey, optValue) in driverOpts {
                //                        networkCreateArgs.append("--opt")
                //                        networkCreateArgs.append("\(optKey)=\(optValue)")
                //                    }
                print("Network Options Detected, But Not Supported")
            }
            // Add various network flags
            if networkConfig?.attachable == true {
                //                    networkCreateArgs.append("--attachable")
                print("Network Attachable Flag Detected, But Not Supported")
            }
            if networkConfig?.enable_ipv6 == true {
                //                    networkCreateArgs.append("--ipv6")
                print("Network IPv6 Flag Detected, But Not Supported")
            }
            if networkConfig?.isInternal == true {
                //                    networkCreateArgs.append("--internal")
                print("Network Internal Flag Detected, But Not Supported")
            }  // CORRECTED: Use isInternal

            // Add labels
            if let labels = networkConfig?.labels, !labels.isEmpty {
                print("Network Labels Detected, But Not Supported")
                //                    for (labelKey, labelValue) in labels {
                //                        networkCreateArgs.append("--label")
                //                        networkCreateArgs.append("\(labelKey)=\(labelValue)")
                //                    }
            }

            print("Creating network: \(networkName) (Actual name: \(actualNetworkName))")
            print("Executing container network create: container \(networkCreateArgs.joined(separator: " "))")
            guard (try? await NetworkClient().get(id: actualNetworkName)) == nil else {
                print("Network '\(networkName)' already exists")
                return
            }
            let commands = [actualNetworkName]
            
            let networkCreate = try Application.NetworkCreate.parse(commands + logging.passThroughCommands())

            try await networkCreate.run()
            print("Network '\(networkName)' created")
        }
    }

    // MARK: Compose Service Level Functions
    private mutating func configService(_ service: Service, serviceName: String, from dockerCompose: DockerCompose) async throws {
        guard let projectName else { throw ComposeError.invalidProjectName }

        try waitForDependencyConditions(serviceName: serviceName, service: service)

        var imageToRun: String
        
        var runCommandArgs: [String] = []

        // Handle 'build' configuration
        if let buildConfig = service.build {
            imageToRun = try await buildService(buildConfig, for: service, serviceName: serviceName)
        } else if let img = service.image {
            // Use specified image if no build config
            // Pull image if necessary
            try await pullImage(img, platform: service.platform)
            imageToRun = img
        } else {
            // Should not happen due to Service init validation, but as a fallback
            throw ComposeError.imageNotFound(serviceName)
        }
        
        // Set Run Platform
        if let platform = service.platform {
            runCommandArgs.append(contentsOf: ["--platform", "\(platform)"])
        }

        // Handle 'deploy' configuration (note that this tool doesn't fully support it)
        if service.deploy != nil {
            print("Note: The 'deploy' configuration for service '\(serviceName)' was parsed successfully.")
            print(
                "However, this 'container-compose' tool does not currently support 'deploy' functionality (e.g., replicas, resources, update strategies) as it is primarily for orchestration platforms like Docker Swarm or Kubernetes, not direct 'container run' commands."
            )
            print("The service will be run as a single container based on other configurations.")
        }

        // Add detach flag if specified on the CLI
        if detach {
            runCommandArgs.append("-d")
        }

        // Determine container name
        let containerName: String
        if let explicitContainerName = service.container_name {
            containerName = explicitContainerName
            print("Info: Using explicit container_name: \(containerName)")
        } else {
            // Default container name based on project and service name
            containerName = "\(projectName)-\(serviceName)"
        }
        runCommandArgs.append("--name")
        runCommandArgs.append(containerName)

        // Apply any user-defined labels, then stamp Docker-Compose-compatible project/service
        // labels so external tools (GUIs, dashboards) can group a stack's containers reliably
        // by label instead of guessing from the `<project>-<service>` name prefix (which
        // mis-groups unrelated containers that merely share a prefix). The compose labels are
        // set last so they take precedence over a user value for the same key; keys are sorted
        // for a deterministic `container run` argv.
        var labels = service.labels ?? [:]
        labels["com.docker.compose.project"] = projectName
        labels["com.docker.compose.service"] = serviceName
        for key in labels.keys.sorted() {
            runCommandArgs.append(contentsOf: ["--label", "\(key)=\(labels[key] ?? "")"])
        }

        // REMOVED: Restart policy is not supported by `container run`
        // if let restart = service.restart {
        //     runCommandArgs.append("--restart")
        //     runCommandArgs.append(restart)
        // }

        // Add user
        if let user = service.user {
            runCommandArgs.append("--user")
            runCommandArgs.append(user)
        }

        // Add volume mounts
        if let volumes = service.volumes {
            for volume in volumes {
                let args = try await configVolume(volume, from: dockerCompose)
                runCommandArgs.append(contentsOf: args)
            }
        }

        // Combine environment variables from .env files and service environment
        var combinedEnv: [String: String] = environmentVariables

        if let envFiles = service.env_file {
            for envFile in envFiles {
                let additionalEnvVars = loadEnvFile(path: URL(fileURLWithPath: envFile, relativeTo: URL(fileURLWithPath: composeDirectory)).path)
                combinedEnv.merge(additionalEnvVars) { (current, _) in current }
            }
        }

        if let serviceEnv = service.environment {
            combinedEnv.merge(serviceEnv) { (old, new) in
                guard !new.contains("${") else {
                    return old
                }
                return new
            }  // Service env overrides .env files
        }

        // Fill in variables
        combinedEnv = combinedEnv.mapValues({ value in
            guard value.contains("${") else { return value }

            let variableName = String(value.replacingOccurrences(of: "${", with: "").dropLast())
            return combinedEnv[variableName] ?? value
        })

        // Fill in IPs
        combinedEnv = combinedEnv.mapValues({ value in
            containerIps[value] ?? value
        })

        // MARK: Spinning Spot
        // Add environment variables to run command
        for (key, value) in combinedEnv {
            runCommandArgs.append("-e")
            runCommandArgs.append("\(key)=\(value)")
        }

         if let ports = service.ports {
             for port in ports {
                 let resolvedPort = resolveVariable(port, with: environmentVariables)
                 runCommandArgs.append("-p")
                 runCommandArgs.append(composePortToRunArg(resolvedPort))
             }
         }

        // Connect to specified networks
        if let serviceNetworks = service.networks {
            for network in serviceNetworks {
                let resolvedNetwork = resolveVariable(network, with: environmentVariables)
                // Use the explicit network name from top-level definition if available, otherwise resolved name
                let networkToConnect = dockerCompose.networks?[network]??.name ?? resolvedNetwork
                runCommandArgs.append("--network")
                runCommandArgs.append(networkToConnect)

                if let aliases = service.networkConfigurations?[network]?.aliases, !aliases.isEmpty {
                    print(
                        "Warning: Service '\(serviceName)' defines network aliases for '\(network)' (\(aliases.joined(separator: ", "))), but Apple Container does not currently expose a container run alias flag."
                    )
                }
            }
            print(
                "Info: Service '\(serviceName)' is configured to connect to networks: \(serviceNetworks.joined(separator: ", ")) ascertained from networks attribute in \(composePath)."
            )
            print(
                "Note: This tool assumes custom networks are defined at the top-level 'networks' key or are pre-existing. This tool does not create implicit networks for services if not explicitly defined at the top-level."
            )
        } else {
            print("Note: Service '\(serviceName)' is not explicitly connected to any networks. It will likely use the default bridge network.")
        }

        // Apple Container 1.0.0 does not expose a `container run` hostname flag.
        let hostnameTranslation = Self.hostnameRunArgs(
            hostname: service.hostname,
            serviceName: serviceName,
            environmentVariables: environmentVariables
        )
        if let warning = hostnameTranslation.warning {
            print(warning)
        }
        runCommandArgs.append(contentsOf: hostnameTranslation.args)

        // Add working directory
        if let workingDir = service.working_dir {
            let resolvedWorkingDir = resolveVariable(workingDir, with: environmentVariables)
            runCommandArgs.append("--workdir")
            runCommandArgs.append(resolvedWorkingDir)
        }

        // Add privileged flag
        if service.privileged == true {
            runCommandArgs.append("--privileged")
        }

        // Add read-only flag
        if service.read_only == true {
            runCommandArgs.append("--read-only")
        }

        // Add resource limits
        if let cpus = service.deploy?.resources?.limits?.cpus {
            runCommandArgs.append(contentsOf: ["--cpus", cpus])
        }
        if let memory = service.deploy?.resources?.limits?.memory {
            runCommandArgs.append(contentsOf: ["--memory", memory])
        }

        // Handle service-level configs (note: still only parsing/logging, not attaching)
        if let serviceConfigs = service.configs {
            print(
                "Note: Service '\(serviceName)' defines 'configs'. Docker Compose 'configs' are primarily used for Docker Swarm deployed stacks and are not directly translatable to 'container run' commands."
            )
            print("This tool will parse 'configs' definitions but will not create or attach them to containers during 'container run'.")
            for serviceConfig in serviceConfigs {
                print(
                    "  - Config: '\(serviceConfig.source)' (Target: \(serviceConfig.target ?? "default location"), UID: \(serviceConfig.uid ?? "default"), GID: \(serviceConfig.gid ?? "default"), Mode: \(serviceConfig.mode?.description ?? "default"))"
                )
            }
        }
        //
        // Handle service-level secrets (note: still only parsing/logging, not attaching)
        if let serviceSecrets = service.secrets {
            print(
                "Note: Service '\(serviceName)' defines 'secrets'. Docker Compose 'secrets' are primarily used for Docker Swarm deployed stacks and are not directly translatable to 'container run' commands."
            )
            print("This tool will parse 'secrets' definitions but will not create or attach them to containers during 'container run'.")
            for serviceSecret in serviceSecrets {
                print(
                    "  - Secret: '\(serviceSecret.source)' (Target: \(serviceSecret.target ?? "default location"), UID: \(serviceSecret.uid ?? "default"), GID: \(serviceSecret.gid ?? "default"), Mode: \(serviceSecret.mode?.description ?? "default"))"
                )
            }
        }

        // Add interactive and TTY flags
        if service.stdin_open == true {
            runCommandArgs.append("-i")  // --interactive
        }
        if service.tty == true {
            runCommandArgs.append("-t")  // --tty
        }

        // Translate `entrypoint` + `command` into the right shape for
        // `container run`. Both can be set together — they are NOT mutually
        // exclusive in Compose semantics — and `--entrypoint` must precede
        // the image. See the helper below for the full mapping.
        let argv = Self.entrypointAndCommandArgs(
            entrypoint: service.entrypoint,
            command: service.command
        )
        if let entrypointFlag = argv.entrypointFlag {
            runCommandArgs.append(contentsOf: ["--entrypoint", entrypointFlag])
        }
        runCommandArgs.append(imageToRun)
        runCommandArgs.append(contentsOf: argv.positional)

        var serviceColor: NamedColor = Self.availableContainerConsoleColors.randomElement()!

        if Array(Set(containerConsoleColors.values)).sorted(by: { $0.rawValue < $1.rawValue }) != Self.availableContainerConsoleColors.sorted(by: { $0.rawValue < $1.rawValue }) {
            while containerConsoleColors.values.contains(serviceColor) {
                serviceColor = Self.availableContainerConsoleColors.randomElement()!
            }
        }

        let selectedColor = serviceColor
        self.containerConsoleColors[serviceName] = selectedColor

        @Sendable
        func handleOutput(_ output: String) {
            print("\(serviceName): \(output)".applyingColor(selectedColor))
        }

        if detach {
            print("\nStarting service: \(serviceName)")
            print("Starting \(serviceName)")
            print("----------------------------------------\n")
            let exitCode = try await streamCommand(
                "container",
                args: ["run"] + runCommandArgs,
                onStdout: handleOutput,
                onStderr: handleOutput
            )
            guard exitCode == 0 else {
                throw ComposeError.containerRunFailed(serviceName, exitCode)
            }
        } else {
            Task { [self, selectedColor] in
                @Sendable
                func handleOutput(_ output: String) {
                    print("\(serviceName): \(output)".applyingColor(selectedColor))
                }

                print("\nStarting service: \(serviceName)")
                print("Starting \(serviceName)")
                print("----------------------------------------\n")
                let exitCode = try await streamCommand(
                    "container",
                    args: ["run"] + runCommandArgs,
                    onStdout: handleOutput,
                    onStderr: handleOutput
                )
                if exitCode != 0 {
                    fputs("Error: Service '\(serviceName)' exited with status \(exitCode).\n", stderr)
                }
            }
        }

        let startState = try await waitUntilServiceStarted(serviceName)
        serviceStartStates[serviceName] = startState

        switch startState {
        case .running:
            try await updateEnvironmentWithServiceIP(serviceName)
            if let healthcheck = service.healthcheck, !healthcheck.isDisabled {
                try await waitUntilServiceIsHealthy(serviceName: serviceName, healthcheck: healthcheck)
                serviceHealth[serviceName] = true
            }
        case .completed:
            if let healthcheck = service.healthcheck, !healthcheck.isDisabled {
                throw ComposeError.healthcheckUnavailable(serviceName)
            }
        }
    }

    private func waitForDependencyConditions(serviceName: String, service: Service) throws {
        for dependencyName in service.depends_on ?? [] {
            let dependency = service.dependencyConditions?[dependencyName] ?? ServiceDependency()
            switch dependency.effectiveCondition {
            case ServiceDependency.serviceStarted:
                guard serviceStartStates[dependencyName] != nil else {
                    throw ComposeError.dependencyNotStarted(serviceName, dependencyName)
                }
            case ServiceDependency.serviceHealthy:
                guard serviceHealth[dependencyName] == true else {
                    throw ComposeError.dependencyNotHealthy(serviceName, dependencyName)
                }
            case ServiceDependency.serviceCompletedSuccessfully:
                guard serviceStartStates[dependencyName] == .completed else {
                    throw ComposeError.dependencyNotCompleted(serviceName, dependencyName)
                }
            default:
                throw ComposeError.unsupportedDependencyCondition(serviceName, dependencyName, dependency.effectiveCondition)
            }
        }
    }

    private func waitUntilServiceIsHealthy(serviceName: String, healthcheck: Healthcheck) async throws {
        guard let projectName else { throw ComposeError.invalidProjectName }
        guard let execArguments = healthcheck.execArguments else {
            return
        }

        let containerName = "\(projectName)-\(serviceName)"
        let retries = max(healthcheck.retries ?? 3, 1)
        let interval = Healthcheck.parseDuration(healthcheck.interval, default: 30)
        let startPeriod = Healthcheck.parseDuration(healthcheck.start_period, default: 0)

        if startPeriod > 0 {
            try await Task.sleep(nanoseconds: UInt64(startPeriod * 1_000_000_000))
        }

        for attempt in 1...retries {
            let exitCode = try await streamCommand(
                "container",
                args: ["exec", containerName] + execArguments,
                onStdout: { _ in },
                onStderr: { _ in }
            )
            if exitCode == 0 {
                return
            }

            if attempt < retries {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }

        throw ComposeError.healthcheckFailed(serviceName)
    }

    private func pullImage(_ imageName: String, platform: String?) async throws {
        let imageList = try await ClientImage.list()
        // An image is considered already-local if any of:
        //   - the stored reference matches `imageName` exactly (multi-path local builds, e.g. `myorg/foo:local`)
        //   - the stored reference is `imageName` with a registry prefix (`docker.io/library/nginx:latest`
        //     when the user wrote `nginx:latest` or `library/nginx:latest`)
        //   - the last `/`-separated component of the stored reference matches `imageName`
        //     (legacy fallback for short references like `alpine:latest`)
        let exists = imageList.contains { ref in
            let stored = ref.description.reference
            return stored == imageName
                || stored.hasSuffix("/\(imageName)")
                || stored.components(separatedBy: "/").last == imageName
        }
        guard !exists else {
            return
        }

        print("Pulling Image \(imageName)...")
        
        var commands = [
            imageName
        ]
        
        if let platform {
            commands.append(contentsOf: ["--platform", platform])
        }

        let imagePull = try Application.ImagePull.parse(commands + logging.passThroughCommands())
        try await imagePull.run()
    }

    /// Builds Docker Service
    ///
    /// - Parameters:
    ///   - buildConfig: The configuration for the build
    ///   - service: The service you would like to build
    ///   - serviceName: The fallback name for the image
    ///
    /// - Returns: Image Name (`String`)
    private func buildService(_ buildConfig: Build, for service: Service, serviceName: String) async throws -> String {
        // Determine image tag for built image
        let imageToRun = service.image ?? "\(serviceName):latest"
        let imageList = try await ClientImage.list()
        if !rebuild, imageList.contains(where: { $0.description.reference.components(separatedBy: "/").last == imageToRun }) {
            return imageToRun
        }

        // Per Compose spec: `context` is relative to the compose file's directory,
        // and `dockerfile` is relative to the resolved `context` (not the compose dir).
        let contextURL = URL(fileURLWithPath: buildConfig.context, relativeTo: URL(fileURLWithPath: composeDirectory))
        var commands = [contextURL.path]

        // Add build arguments
        for (key, value) in buildConfig.args ?? [:] {
            commands.append(contentsOf: ["--build-arg", "\(key)=\(resolveVariable(value, with: environmentVariables))"])
        }

        // Add Dockerfile path
        commands.append(contentsOf: ["--file", URL(fileURLWithPath: buildConfig.dockerfile ?? "Dockerfile", relativeTo: contextURL).path])
        
        // Add caching options
        if noCache {
            commands.append("--no-cache")
        }
        
        // Add OS/Arch
        let split = service.platform?.split(separator: "/")
        let os = String(split?.first ?? "linux")
        let arch = String(((split ?? []).count >= 1 ? split?.last : nil) ?? "arm64")
        commands.append(contentsOf: ["--os", os])
        commands.append(contentsOf: ["--arch", arch])
        
        // Add image name
        commands.append(contentsOf: ["--tag", imageToRun])
        
        // Add CPU & Memory
        let cpuCount = Int64(service.deploy?.resources?.limits?.cpus ?? "2") ?? 2
        let memoryLimit = service.deploy?.resources?.limits?.memory ?? "2048MB"
        commands.append(contentsOf: ["--cpus", "\(cpuCount)"])
        commands.append(contentsOf: ["--memory", memoryLimit])

        var buildCommand = try Application.BuildCommand.parse(commands)
        print("\n----------------------------------------")
        print("Building image for service: \(serviceName) (Tag: \(imageToRun))")
        try buildCommand.validate()
        try await buildCommand.run()
        print("Image build for \(serviceName) completed.")
        print("----------------------------------------")

        return imageToRun
    }

    private func configVolume(_ volume: String, from dockerCompose: DockerCompose) async throws -> [String] {
        try composeVolumeToRunArgs(
            volume,
            cwd: cwd,
            fileManager: fileManager,
            environmentVariables: environmentVariables,
            projectName: projectName,
            volumeDefinitions: dockerCompose.volumes
        )
    }
}

// MARK: CommandLine Functions
extension ComposeUp {

    /// Runs a command, streams stdout and stderr via closures, and completes when the process exits.
    ///
    /// - Parameters:
    ///   - command: The name of the command to run (e.g., `"container"`).
    ///   - args: Command-line arguments to pass to the command.
    ///   - onStdout: Closure called with streamed stdout data.
    ///   - onStderr: Closure called with streamed stderr data.
    /// - Returns: The process's exit code.
    /// - Throws: If the process fails to launch.
    @discardableResult
    func streamCommand(
        _ command: String,
        args: [String] = [],
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
}
