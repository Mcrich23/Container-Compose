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
import ContainerCommands
import ContainerAPIClient
import Foundation

public struct ComposeRun: AsyncParsableCommand, @unchecked Sendable {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "run",
        abstract: "Run a one-off command on a service",
        discussion: """
            The trailing COMMAND overrides the service command. The service ports
            are not mapped unless --service-ports is given. Dependencies are
            started detached first unless --no-deps is given.

            -e/--env, -u/--user, -i/--interactive and -t/--tty are shared process
            flags with the same meaning as docker run. There is no -w/--workdir
            override: -w is reserved for the local working directory, so set
            working_dir in the compose file instead.
            """
    )

    @Argument(help: "Service to run a one-off command on")
    var service: String

    @Argument(parsing: .remaining, help: "Command and arguments overriding the service command")
    var command: [String] = []

    @Flag(name: [.customShort("d"), .customLong("detach")], help: "Run container in background")
    var detach: Bool = false

    @Flag(name: .long, help: "Automatically remove the container when it exits")
    var rm: Bool = false

    @Flag(name: .customLong("no-deps"), help: "Don't start linked services")
    var noDeps: Bool = false

    @Flag(name: [.customShort("P"), .customLong("service-ports")], help: "Map the service ports to the host")
    var servicePorts: Bool = false

    @Option(name: [.customShort("p"), .customLong("publish")], help: "Publish a container port to the host")
    var publish: [String] = []

    @Option(name: .customLong("env-from-file"), help: "Read environment variables from a file")
    var envFromFile: [String] = []

    @Option(name: [.short, .customLong("volume")], help: "Bind mount a volume (source:destination[:mode])")
    var volume: [String] = []

    @Option(name: [.short, .customLong("label")], help: "Add a label (key=value)")
    var label: [String] = []

    @Option(name: .customLong("entrypoint"), help: "Override the image entrypoint")
    var entrypoint: String?

    @Option(name: .long, help: "Assign a name to the one-off container")
    var name: String?

    @Flag(name: .long, help: "Build the image before running")
    var build: Bool = false

    @Flag(name: .long, help: "Do not use cache when building")
    var noCache: Bool = false

    @Flag(name: [.customShort("T"), .customLong("no-tty")], help: "Disable pseudo-TTY allocation")
    var noTTY: Bool = false

    @OptionGroup
    var projectOptions: ComposeProjectOptions

    @OptionGroup
    var logging: Flags.Logging

    private var composeDirectory: String { projectOptions.composeDirectory }
    private var cwd: String { projectOptions.cwd }

    func baseArgs() -> [String] {
        var args: [String] = []
        if let file = projectOptions.composeFileOptions.composeFilename {
            args.append(contentsOf: ["-f", file])
        }
        for profile in projectOptions.composeFileOptions.profile {
            args.append(contentsOf: ["--profile", profile])
        }
        if let cwd = projectOptions.process.cwd {
            args.append(contentsOf: ["--workdir", cwd])
        }
        for envFile in projectOptions.process.envFile {
            args.append(contentsOf: ["--env-file", envFile])
        }
        if projectOptions.process.interactive {
            args.append("-i")
        }
        if projectOptions.process.tty {
            args.append("-t")
        }
        if let user = projectOptions.process.user {
            args.append(contentsOf: ["-u", user])
        }
        for env in projectOptions.process.env {
            args.append(contentsOf: ["-e", env])
        }
        if logging.debug {
            args.append("--debug")
        }
        return args
    }

    public mutating func run() async throws {
        let project = try projectOptions.resolve(filteringBy: [service])
        let dockerCompose = project.compose
        let projectName = project.projectName
        let baseEnv = loadEnvFile(path: projectOptions.envFilePath)

        let allServices: [(serviceName: String, service: Service)] = dockerCompose.services.compactMap { name, svc in
            guard let svc else { return nil }
            return (name, svc)
        }
        try Service.validateRequestedServices([service], against: allServices)
        guard let target = project.services.first(where: { $0.serviceName == service }) else {
            throw ComposeError.noSuchService(service)
        }
        let svc = target.service
        let deps = project.services.filter { $0.serviceName != service }

        var depIPs: [String: String] = [:]
        if !noDeps, !deps.isEmpty {
            var pending: [String] = []
            for dep in deps where !(await Self.containerRunning(names: dep.candidateContainerNames)) {
                pending.append(dep.serviceName)
            }
            if !pending.isEmpty {
                print("Starting dependencies: \(pending.joined(separator: ", "))")
                var up = try ComposeUp.parse(baseArgs() + ["-d"] + pending)
                try await up.run()
            }
            for dep in deps {
                if let ip = await Self.firstIPv4(names: dep.candidateContainerNames) {
                    depIPs[dep.serviceName] = ip
                }
            }
        }

        var imageToRun: String
        if svc.build != nil {
            let tag = svc.image ?? "\(service):latest"
            let imageMissing = try await !Self.imageExistsLocally(tag)
            if build || imageMissing {
                var buildArgs = baseArgs() + [service]
                if noCache {
                    buildArgs.insert("--no-cache", at: 0)
                }
                var buildCommand = try ComposeBuild.parse(buildArgs)
                try await buildCommand.run()
            }
            imageToRun = tag
        } else if let img = svc.image {
            try await Self.pullImageIfMissing(img, platform: svc.platform, logging: logging)
            imageToRun = img
        } else {
            throw ComposeError.imageNotFound(service)
        }

        if let networks = dockerCompose.networks {
            for (networkName, networkConfig) in networks {
                try await Self.ensureNetwork(
                    name: networkConfig?.name ?? networkName,
                    external: networkConfig?.external?.isExternal == true,
                    logging: logging
                )
            }
        }
        if let volumes = dockerCompose.volumes {
            for (volumeName, volumeConfig) in volumes {
                guard let volumeConfig else { continue }
                try await Self.ensureVolume(name: volumeName, config: volumeConfig, projectName: projectName)
            }
        }

        var dnsDomain: String?
        var dnsAvailable = false
        if let derived = ComposeProject.sanitizeDnsDomain(projectName) {
            dnsDomain = derived
            dnsAvailable = await Self.dnsDomainRegistered(derived)
        }

        var runCommandArgs: [String] = []
        var oneOffHostsFilePath: String?
        if let platform = svc.platform {
            runCommandArgs.append(contentsOf: ["--platform", platform])
        }
        if detach {
            runCommandArgs.append("-d")
        }
        if rm {
            runCommandArgs.append("--rm")
        }
        let runName = name ?? Self.oneOffContainerName(projectName: projectName, serviceName: service)
        runCommandArgs.append(contentsOf: ["--name", runName])
        if dnsAvailable, let dnsDomain {
            runCommandArgs.append(contentsOf: ["--dns-domain", dnsDomain])
        }

        var labels = svc.labels ?? [:]
        labels.merge(Self.parseLabelOverrides(label)) { _, new in new }
        labels["com.docker.compose.project"] = projectName
        labels["com.docker.compose.service"] = service
        labels["com.docker.compose.oneoff"] = "True"
        for key in labels.keys.sorted() {
            runCommandArgs.append(contentsOf: ["--label", "\(key)=\(labels[key] ?? "")"])
        }

        if let effectiveUser = projectOptions.process.user ?? svc.user {
            runCommandArgs.append(contentsOf: ["--user", effectiveUser])
        }

        if let volumes = svc.volumes {
            for entry in volumes {
                runCommandArgs.append(contentsOf: try composeVolumeToRunArgs(
                    entry, cwd: cwd, environmentVariables: baseEnv,
                    projectName: projectName, volumeDefinitions: dockerCompose.volumes
                ))
            }
        }
        for entry in volume {
            runCommandArgs.append(contentsOf: try composeVolumeToRunArgs(
                entry, cwd: cwd, environmentVariables: baseEnv,
                projectName: projectName, volumeDefinitions: dockerCompose.volumes
            ))
        }

        var combinedEnv = Self.baseEnvironment(service: svc, composeDirectory: composeDirectory, baseEnv: baseEnv)
        for file in envFromFile {
            let vars = loadEnvFile(path: resolvedPath(for: file, relativeTo: URL(fileURLWithPath: composeDirectory)))
            combinedEnv.merge(vars) { _, new in new }
        }
        combinedEnv.merge(Self.parseEnvOverrides(projectOptions.process.env, base: combinedEnv)) { _, new in new }
        combinedEnv = combinedEnv.mapValues { depIPs[$0] ?? $0 }
        for (key, value) in combinedEnv {
            runCommandArgs.append(contentsOf: ["-e", "\(key)=\(value)"])
        }

        if servicePorts, let ports = svc.ports {
            for port in ports {
                runCommandArgs.append(contentsOf: ["-p", composePortToRunArg(resolveVariable(port, with: baseEnv))])
            }
        }
        for spec in publish {
            runCommandArgs.append(contentsOf: ["-p", composePortToRunArg(resolveVariable(spec, with: baseEnv))])
        }

        if let serviceNetworks = svc.networks {
            for network in serviceNetworks {
                let resolvedNetwork = resolveVariable(network, with: baseEnv)
                let networkToConnect = dockerCompose.networks?[network]??.name ?? resolvedNetwork
                let translation = ComposeUp.networkRunArg(
                    network: networkToConnect,
                    aliases: svc.networkConfigurations?[network]?.aliases ?? [],
                    serviceName: service,
                    environmentVariables: baseEnv
                )
                runCommandArgs.append(contentsOf: ["--network", translation.arg])
                if let warning = translation.warning {
                    print(warning)
                }
            }
        }

        let hostnameTranslation = ComposeUp.hostnameRunArgs(
            hostname: svc.hostname, serviceName: service, environmentVariables: baseEnv
        )
        if let warning = hostnameTranslation.warning {
            print(warning)
        }

        if let extraHosts = svc.extra_hosts, !extraHosts.isEmpty {
            let resolvedEntries = extraHosts.map { resolveVariable($0, with: baseEnv) }
            let needsGateway = resolvedEntries.contains { $0.hasSuffix(":host-gateway") }
            let resolvedNetworkName = svc.networks?.first.map { resolveVariable($0, with: baseEnv) } ?? "default"
            let hostGatewayIP = needsGateway ? ComposeUp.resolveHostGatewayIP(networkName: resolvedNetworkName) : ""
            var hostsFileLines = ["127.0.0.1 localhost", "::1 localhost"]
            var seenHostnames: Set<String> = ["localhost"]
            for resolved in resolvedEntries {
                let parts = resolved.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                hostsFileLines.append("\(parts[1] == "host-gateway" ? hostGatewayIP : parts[1]) \(parts[0])")
                seenHostnames.insert(parts[0])
            }
            let ownHostname = svc.hostname.map { resolveVariable($0, with: baseEnv) } ?? runName
            if !seenHostnames.contains(ownHostname) {
                hostsFileLines.append("127.0.0.1 \(ownHostname)")
            }
            let hostsFilePath = ComposeUp.runExtraHostsFilePath(projectName: projectName, containerName: runName)
            do {
                try (hostsFileLines.joined(separator: "\n") + "\n").write(toFile: hostsFilePath, atomically: true, encoding: .utf8)
                runCommandArgs.append(contentsOf: ["-v", "\(hostsFilePath):/etc/hosts"])
                oneOffHostsFilePath = hostsFilePath
            } catch {
                print("Warning: could not write hosts file for service '\(service)' extra_hosts at \(hostsFilePath): \(error.localizedDescription)")
            }
        }

        if let workingDir = svc.working_dir {
            runCommandArgs.append(contentsOf: ["--workdir", resolveVariable(workingDir, with: baseEnv)])
        }
        if svc.privileged == true {
            print("Note: Service '\(service)' requests privileged mode; Apple Container does not support --privileged; ignoring.")
        }
        if svc.read_only == true {
            runCommandArgs.append("--read-only")
        }
        let resources = ResourceArguments.runArgs(
            for: svc,
            serviceName: service,
            environmentVariables: baseEnv
        )
        runCommandArgs.append(contentsOf: resources.args)
        for note in resources.notes {
            print(note)
        }

        let interactive = !detach && (projectOptions.process.interactive || (svc.stdin_open ?? true))
        let stdinIsTTY = isatty(STDIN_FILENO) != 0
        let useTTY = interactive && !noTTY && (projectOptions.process.tty || (svc.tty ?? stdinIsTTY))
        if interactive {
            runCommandArgs.append("-i")
        }
        if useTTY {
            runCommandArgs.append("-t")
        }

        let argv = ComposeUp.entrypointAndCommandArgs(
            entrypoint: entrypoint.map { [$0] } ?? svc.entrypoint,
            command: command.isEmpty ? svc.command : command
        )
        if let entrypointFlag = argv.entrypointFlag {
            runCommandArgs.append(contentsOf: ["--entrypoint", entrypointFlag])
        }
        runCommandArgs.append(imageToRun)
        runCommandArgs.append(contentsOf: argv.positional)

        try await Self.reclaimRunName(runName, rm: rm)

        let containerArgs = runCommandArgs + logging.passThroughCommands()
        if detach {
            print("Running one-off command on service '\(service)' in background as '\(runName)'")
        }
        let containerRun = try Application.ContainerRun.parse(containerArgs)
        do {
            try await containerRun.run()
        } catch {
            // Detached failures can leave the container auto-removing, so only
            // delete the file if no container claims it; foreground runs know
            // exactly when the container has finished.
            await Self.cleanupOneOffHostsFile(
                oneOffHostsFilePath,
                containerName: runName,
                autoRemove: rm && !detach
            )
            throw error
        }
        if !detach {
            await Self.cleanupOneOffHostsFile(oneOffHostsFilePath, containerName: runName, autoRemove: rm)
        }
    }

    /// Removes a one-off run's generated /etc/hosts file once it can no longer
    /// be needed: immediately when the container auto-removes (`--rm`),
    /// otherwise only if the container is gone. A stopped container may be
    /// started again and still needs its bind-mounted file, so those are left
    /// for `ComposeDown`'s sweep. Detached runs exit the CLI immediately and
    /// likewise rely on the sweep.
    static func cleanupOneOffHostsFile(_ path: String?, containerName: String, autoRemove: Bool) async {
        guard let path else { return }
        if !autoRemove {
            let client = ContainerClient()
            guard (try? await client.get(id: containerName)) == nil else { return }
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    static func oneOffContainerName(projectName: String, serviceName: String, suffix: String? = nil) -> String {
        let resolvedSuffix = suffix ?? String((0..<6).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        return "\(projectName)-\(serviceName)-run-\(resolvedSuffix)"
    }

    static func baseEnvironment(service svc: Service, composeDirectory: String, baseEnv: [String: String]) -> [String: String] {
        var combined = baseEnv
        if let envFiles = svc.env_file {
            for envFile in envFiles {
                let additional = loadEnvFile(path: URL(fileURLWithPath: envFile, relativeTo: URL(fileURLWithPath: composeDirectory)).path)
                combined.merge(additional) { current, _ in current }
            }
        }
        if let serviceEnv = svc.environment {
            combined.merge(serviceEnv) { old, new in
                guard !new.contains("${") else {
                    return old
                }
                return new
            }
        }
        return combined.mapValues { value in
            guard value.contains("${") else { return value }
            let variableName = String(value.replacingOccurrences(of: "${", with: "").dropLast())
            return combined[variableName] ?? value
        }
    }

    static func parseEnvOverrides(_ entries: [String], base: [String: String]) -> [String: String] {
        Service.parseEnvironmentList(entries).mapValues { resolveVariable($0, with: base) }
    }

    static func parseLabelOverrides(_ entries: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for entry in entries {
            if let index = entry.firstIndex(of: "=") {
                result[String(entry[..<index])] = String(entry[entry.index(after: index)...])
            } else {
                result[entry] = ""
            }
        }
        return result
    }

    static func imageExistsLocally(_ imageName: String) async throws -> Bool {
        let imageList = try await ClientImage.list()
        return imageList.contains { ref in
            let stored = ref.description.reference
            return stored == imageName
                || stored.hasSuffix("/\(imageName)")
                || stored.components(separatedBy: "/").last == imageName
        }
    }

    static func pullImageIfMissing(_ imageName: String, platform: String?, logging: Flags.Logging) async throws {
        guard try await !imageExistsLocally(imageName) else {
            return
        }
        print("Pulling Image \(imageName)...")
        var commands = [imageName]
        if let platform {
            commands.append(contentsOf: ["--platform", platform])
        }
        let imagePull = try Application.ImagePull.parse(commands + logging.passThroughCommands())
        try await imagePull.run()
    }

    static func reclaimRunName(_ runName: String, rm: Bool) async throws {
        let client = ContainerClient()
        guard let existing = try? await client.get(id: runName) else {
            return
        }
        if rm {
            print("Removing existing one-off container '\(runName)' (--rm).")
            try? await client.stop(id: existing.id)
            try await client.delete(id: existing.id)
        } else {
            throw ComposeError.containerNameTaken(runName)
        }
    }

    static func containerRunning(names: [String]) async -> Bool {
        let client = ContainerClient()
        for name in names {
            if let container = try? await client.get(id: name), container.status == .running {
                return true
            }
        }
        return false
    }

    static func firstIPv4(names: [String]) async -> String? {
        let client = ContainerClient()
        for name in names {
            if let container = try? await client.get(id: name),
               let ip = container.networks.compactMap({ $0.ipv4Address.address.description }).first {
                return ip
            }
        }
        return nil
    }

    static func dnsDomainRegistered(_ domain: String) async -> Bool {
        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = ["container", "system", "dns", "list"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return false }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return ComposeUp.dnsListContainsDomain(String(data: data, encoding: .utf8) ?? "", domain: domain)
    }

    static func ensureNetwork(name: String, external: Bool, logging: Flags.Logging) async throws {
        if external {
            print("Info: Network '\(name)' is declared as external.")
            print("This tool assumes external network '\(name)' already exists and will not attempt to create it.")
            return
        }
        guard (try? await NetworkClient().get(id: name)) == nil else {
            return
        }
        print("Creating network: \(name)")
        let networkCreate = try Application.NetworkCreate.parse([name] + logging.passThroughCommands())
        try await networkCreate.run()
    }

    static func ensureVolume(name: String, config: Volume, projectName: String) async throws {
        let actualVolumeName = composeNamedVolumeName(
            source: name,
            projectName: projectName,
            volumeDefinition: config
        )
        if config.external?.isExternal == true {
            print("Info: Volume '\(name)' is declared as external.")
            print("This tool assumes external volume '\(actualVolumeName)' already exists and will not attempt to create it.")
            return
        }
        if (try? await ClientVolume.inspect(actualVolumeName)) != nil {
            return
        }
        print("Creating volume: \(name) (Actual name: \(actualVolumeName))")
        _ = try await ClientVolume.create(
            name: actualVolumeName,
            driver: config.driver ?? "local",
            driverOpts: config.driver_opts ?? [:],
            labels: config.labels ?? [:]
        )
    }
}
