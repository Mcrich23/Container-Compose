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
import ContainerXPC
import ContainerizationExtras
import Foundation
@preconcurrency import Rainbow
import Yams

private enum ServiceStartState: Codable, Equatable {
    case running
    case completed
}

// `containerWait` must be registered while the runtime client is still alive;
// once a fast one-shot reaches `.stopped`, the server can no longer recover it.
private actor ServiceExitCodeRegistry {
    static let shared = ServiceExitCodeRegistry()

    private var tasks: [String: Task<Int32, Error>] = [:]

    func set(_ task: Task<Int32, Error>, for containerName: String) {
        tasks[containerName] = task
    }

    func task(for containerName: String) -> Task<Int32, Error>? {
        tasks[containerName]
    }

    func remove(for containerName: String) {
        tasks[containerName] = nil
    }
}

/// Tracks the lifetime of an attached (non-detached) `container run` subprocess.
///
/// Apple Container reports a container as `.stopped` throughout the image/kernel
/// fetch and only flips it to `.running` once init starts. `waitUntilServiceStarted`
/// therefore must not treat that pre-running `.stopped` as a completed one-shot.
/// For an attached run the subprocess itself is the authoritative signal: while
/// it is still alive the container is still starting; once it returns an exit
/// code, the container has finished (a genuine one-shot).
private actor ForegroundRunHandle {
    private var exitCode: Int32? = nil

    func complete(_ code: Int32) { exitCode = code }

    /// The run subprocess's exit code, or `nil` while it is still running.
    func exitCodeIfCompleted() -> Int32? { exitCode }
}

public struct ComposeUp: AsyncParsableCommand, @unchecked Sendable {
    public init() {}

    private static let networkAliasesSupported = supportsNetworkAliases()

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
    /// Apple `container` DNS domain to use for inter-container resolution. Derived
    /// from `projectName` (sanitized to a valid DNS label). `nil` if the project
    /// name produces no usable label.
    private var dnsDomain: String?
    /// True when `dnsDomain` is registered with `container system dns create`,
    /// which means the daemon's embedded DNS server will answer for `*.<dnsDomain>`
    /// queries from inside containers. When true, services get a dotted `--name`
    /// + `--dns-domain` and the /etc/hosts cross-patcher is skipped.
    private var dnsAvailable: Bool = false
    private var environmentVariables: [String: String] = [:]
    private var containerIps: [String: String] = [:]
    private var serviceStartStates: [String: ServiceStartState] = [:]
    private var serviceHealth: [String: Bool] = [:]
    /// Resolved container ID (i.e. the name on disk) per service.
    /// Equal to `service.container_name` when set, otherwise either
    /// `<serviceName>.<dnsDomain>` (DNS path) or `<projectName>-<serviceName>` (legacy).
    private var serviceContainerNames: [String: String] = [:]
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
                "Note: The 'name' field affects generated container names and default named-volume names. Full project-level isolation for other resources is not implemented by this tool."
            )
        } else {
            projectName = deriveProjectName(cwd: cwd)
            print("Info: No 'name' field found in docker-compose.yml. Using directory name as project name: \(projectName ?? "")")
        }

        // Determine whether real DNS is available for this project. If so, we'll
        // give every container a dotted name (`<svc>.<dnsDomain>`) and pass
        // `--dns-domain` so libc inside the container resolves peers via the
        // daemon's DNS server. If not, fall back to /etc/hosts patching.
        if let derived = Self.sanitizeDnsDomain(projectName ?? "") {
            dnsDomain = derived
            dnsAvailable = await checkDnsDomainRegistered(derived)
            if dnsAvailable {
                print("Info: DNS domain '\(derived)' is registered. Using real DNS for inter-container resolution.")
            } else {
                print("""
                Note: DNS domain '\(derived)' is not registered. Inter-container hostname
                      resolution will fall back to /etc/hosts patching. For real DNS:
                          sudo container system dns create \(derived)
                """)
            }
        }

        // Get Services to use
        var services: [(serviceName: String, service: Service)] = dockerCompose.services.compactMap({ serviceName, service in
            guard let service else { return nil }
            return (serviceName, service)
        })
        services = try Service.topoSortConfiguredServices(services)

        // Filter for specified services and active Compose profiles
        services = Service.selectServices(
            from: services,
            requestedServices: self.services,
            activeProfiles: composeFileOptions.activeProfiles
        )

        // Stop Services. Pass every name a previous run might have used (legacy
        // dashed, dotted DNS-mode, and explicit container_name) so the cleanup
        // catches whichever shape exists on disk.
        let containerNamesToStop: [String] = services.flatMap { (serviceName, service) -> [String] in
            var names: [String] = []
            if let projectName { names.append("\(projectName)-\(serviceName)") }
            if let dnsDomain { names.append("\(serviceName).\(dnsDomain)") }
            if let explicit = service.container_name, !names.contains(explicit) { names.append(explicit) }
            return names
        }
        try await stopExistingContainers(containerNamesToStop, remove: true)

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
            await runForegroundUntilStopped(containerNames: services.map({ containerName(for: $0.serviceName) }))
        }
    }

    /// Foreground (`up` without `--detach`) behavior, matching `docker compose up`:
    ///   - Ctrl-C (SIGINT) / `kill` (SIGTERM) gracefully stops the project's
    ///     containers, then exits. A second signal forces an immediate exit.
    ///   - If the containers stop on their own — or via `container compose down`
    ///     from another shell — `up` returns instead of hanging forever.
    ///
    /// Takes resolved container names (not service names): a service's container
    /// may be named via explicit `container_name` or the dotted
    /// `<service>.<dnsDomain>` DNS convention, not just `<project>-<service>`.
    func runForegroundUntilStopped(containerNames: [String]) async -> Never {
        // Exit once the containers stop by themselves or are stopped externally.
        if !containerNames.isEmpty {
            Task {
                await Self.waitUntilAllContainersStopped(containerNames)
                print("\nAll containers have stopped.")
                Foundation.exit(0)
            }
        }

        // Bridge SIGINT/SIGTERM into an async stream. The `ContainerCommands`
        // invoked during `up` leave these signals neutered (SIG_IGN) via
        // ContainerAPIService's async signal machinery, so a foreground `up`
        // previously ignored Ctrl-C. A `DispatchSource` signal source observes
        // them regardless of disposition.
        let signals = Self.makeSignalStream([SIGINT, SIGTERM])
        var stopping = false
        for await _ in signals {
            if !stopping {
                stopping = true
                print("\nGracefully stopping... (press Ctrl+C again to force)")
                Task {
                    await Self.stopContainers(containerNames)
                    Foundation.exit(0)
                }
            } else {
                print("\nForcing stop.")
                Task {
                    await Self.killContainers(containerNames)
                    Foundation.exit(130)
                }
            }
        }
        Foundation.exit(0)
    }

    /// An `AsyncStream` of the given signals, delivered via `DispatchSource` so
    /// they're received even after the disposition has been set to `SIG_IGN`.
    private static func makeSignalStream(_ signals: [Int32]) -> AsyncStream<Int32> {
        AsyncStream { continuation in
            let queue = DispatchQueue(label: "container-compose.signals")
            let sources: [DispatchSourceSignal] = signals.map { sig in
                // Ignore the default action so the DispatchSource alone handles it.
                signal(sig, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
                source.setEventHandler { continuation.yield(sig) }
                source.resume()
                return source
            }
            continuation.onTermination = { _ in sources.forEach { $0.cancel() } }
        }
    }

    /// Gracefully stops (without removing) the named containers — the
    /// `docker compose up` Ctrl-C contract leaves stopped containers in place.
    private static func stopContainers(_ containerNames: [String]) async {
        let client = ContainerClient()
        for name in containerNames {
            guard let container = try? await client.get(id: name) else { continue }
            print("Stopping container: \(name)")
            do {
                try await client.stop(id: container.id)
            } catch {
                print("Error stopping container \(name): \(error)")
            }
        }
    }

    /// Force-stops the named containers with SIGKILL — the second-Ctrl-C
    /// contract, matching `docker compose up`'s "press Ctrl+C again to force".
    private static func killContainers(_ containerNames: [String]) async {
        let client = ContainerClient()
        for name in containerNames {
            guard let container = try? await client.get(id: name) else { continue }
            print("Killing container: \(name)")
            try? await client.kill(id: container.id, signal: "SIGKILL")
        }
    }

    /// Polls until every named container has been observed running at least once
    /// and then none remain running (stopped naturally or via `down`). Requiring
    /// "seen running first" avoids returning before the containers have started.
    private static func waitUntilAllContainersStopped(_ containerNames: [String], interval: TimeInterval = 1.0) async {
        let client = ContainerClient()
        // `runForegroundUntilStopped` is only reached after `configService` has
        // already confirmed every container started (running or completed), so
        // treat them all as already observed: a `.stopped` container from here on
        // is one that exited, not one that hasn't started yet. Without this, a
        // fast one-shot that exits before the first poll would never be observed
        // `.running` and foreground `up` would hang forever.
        var seenRunning = Set<String>(containerNames)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            var running = Set<String>()
            for name in containerNames {
                if let container = try? await client.get(id: name), container.status == .running {
                    running.insert(name)
                }
            }
            seenRunning.formUnion(running)
            if seenRunning.count == containerNames.count && running.isEmpty {
                return
            }
        }
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

    static func networkRunArg(
        network: String,
        aliases: [String],
        serviceName: String,
        environmentVariables: [String: String],
        supportsAliases: Bool = networkAliasesSupported
    ) -> (arg: String, warning: String?) {
        let resolvedUserAliases = aliases
            .map { resolveVariable($0, with: environmentVariables) }
            .reduce(into: [String]()) { result, alias in
                guard !alias.isEmpty, !result.contains(alias) else { return }
                result.append(alias)
            }
        // Also advertise the service name as an alias so a runtime that supports
        // them can resolve `<service>` without /etc/hosts patching.
        let resolvedAliases = ([serviceName] + resolvedUserAliases)
            .reduce(into: [String]()) { result, alias in
                guard !result.contains(alias) else { return }
                result.append(alias)
            }

        if supportsAliases {
            let aliasProperties = resolvedAliases.map { "alias=\($0)" }.joined(separator: ",")
            return ("\(network),\(aliasProperties)", nil)
        }

        // Apple Container's `container run` only accepts the `mac` and `mtu`
        // network properties — there is no `alias`. Drop them and rely on
        // /etc/hosts patching for service-name resolution. Only warn when the
        // user explicitly declared aliases; the implicit service-name alias is
        // an internal detail and its absence is already covered by the hosts
        // fallback, so it would just be noise on every networked service.
        let warning: String? = resolvedUserAliases.isEmpty
            ? nil
            : "Warning: Service '\(serviceName)' declares network aliases for '\(network)' "
                + "(\(resolvedUserAliases.joined(separator: ", "))), but Apple Container does not "
                + "support them; ignoring. Service-name resolution still works via /etc/hosts."
        return (network, warning)
    }

    private static func supportsNetworkAliases() -> Bool {
        // Apple Container's `container run` does not support network aliases: the
        // daemon accepts only the `mac` and `mtu` network properties and rejects
        // `alias` with "unknown network property 'alias'. Available properties:
        // mac, mtu". The previous probe tested container-compose's own
        // ArgumentParser model (`Application.ContainerRun.parse`), which accepts
        // any `key=value`, so it always reported support — which made
        // `networkRunArg` emit `alias=<service>` for every service on a custom
        // network and break startup. Return false until Apple Container gains
        // alias support.
        return false
    }

    /// Parses a Compose memory string (e.g. `"128m"`, `"2g"`, `"512"`) into bytes.
    /// Units are binary (1k = 1024), matching how Apple Container interprets
    /// `--memory` (`128m` → 134217728 = 128 MiB). Returns `nil` when the value
    /// can't be parsed, so callers can fall back to passing it through verbatim.
    static func parseMemoryToBytes(_ value: String) -> Int64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // Split the leading number from the unit suffix.
        guard let split = trimmed.firstIndex(where: { !$0.isNumber && $0 != "." }) else {
            // Bare number → bytes.
            return Int64(trimmed)
        }
        let numberPart = String(trimmed[..<split])
        let unit = String(trimmed[split...]).filter { $0.isLetter }
        guard let amount = Double(numberPart) else { return nil }

        let multiplier: Int64
        switch unit {
        case "", "b": multiplier = 1
        case "k", "kb", "kib": multiplier = 1_024
        case "m", "mb", "mib": multiplier = 1_024 * 1_024
        case "g", "gb", "gib": multiplier = 1_024 * 1_024 * 1_024
        default: return nil
        }
        return Int64(amount * Double(multiplier))
    }

    /// Apple Container enforces a 200 MiB minimum container memory size and rejects
    /// anything smaller with a confusing daemon error. Clamp sub-minimum values up
    /// to 200 MiB so common Docker values like `mem_limit: 128m` keep working.
    /// Returns the value to pass to `--memory` and whether it was raised.
    static func clampMemoryLimit(_ value: String) -> (value: String, clamped: Bool) {
        let minimumBytes: Int64 = 200 * 1_024 * 1_024
        if let bytes = parseMemoryToBytes(value), bytes < minimumBytes {
            return ("200m", true)
        }
        return (value, false)
    }

    static func validateStoppedServiceExitCode(_ exitCode: Int32, serviceName: String) throws {
        guard exitCode == 0 else {
            throw ComposeError.containerRunFailed(serviceName, exitCode)
        }
    }

    private func containerName(for serviceName: String) -> String {
        if let explicit = serviceContainerNames[serviceName] { return explicit }
        if let projectName { return "\(projectName)-\(serviceName)" }
        return serviceName
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

    /// Pure parser for `container system dns list` output. Output looks like:
    ///     DOMAIN
    ///     foo
    ///     bar
    /// Each non-header line is a registered domain; header is `DOMAIN`.
    static func dnsListContainsDomain(_ output: String, domain: String) -> Bool {
        for raw in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "DOMAIN" { continue }
            if line == domain { return true }
        }
        return false
    }

    /// Checks whether `domain` has been registered via `container system dns create`.
    /// Returns `false` if the CLI is missing, the call fails, or the domain isn't listed.
    private func checkDnsDomainRegistered(_ domain: String) async -> Bool {
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
        let text = String(data: data, encoding: .utf8) ?? ""
        return Self.dnsListContainsDomain(text, domain: domain)
    }

    private func getIPForRunningService(_ serviceName: String) async throws -> String? {
        let name = containerName(for: serviceName)

        let client = ContainerClient()
        let container = try await client.get(id: name)
        // Use the container's own address, not the network gateway — every
        // container on a network shares the same gateway, so substituting the
        // gateway broke service-name -> IP environment resolution.
        let ip = container.networks.compactMap { $0.ipv4Address.address.description }.first

        return ip
    }

    /// Repeatedly polls until the named container reports `running`.
    ///
    /// The container is launched by a `container run` subprocess that may first
    /// download images — notably the one-time ~64 MB init image — and that pull
    /// happens *inside* this wait window. A fixed wall-clock timeout therefore
    /// aborted mid-download on slow connections (`up -d` failing with
    /// "Timed out waiting for container ... to be running").
    ///
    /// Instead we use an *idle* timeout: the run subprocess streams pull/startup
    /// progress into `activity`, so we only give up after `idleTimeout` seconds
    /// with no output *and* the container still not running — i.e. genuinely
    /// stuck, not merely slow. Mirrors `docker compose up`, which shows pull
    /// progress and doesn't bail during an active download.
    ///
    /// On top of the idle timeout we keep an absolute `maxWait` backstop: a
    /// container that keeps dribbling output every few seconds without ever
    /// reaching `running` would otherwise refresh `activity` forever and hang
    /// `up -d` indefinitely. The backstop bounds that pathological case while
    /// still leaving plenty of room for a genuinely slow (but progressing) pull.
    /// - Parameters:
    ///   - serviceName: Compose service name; the container is `<project>-<service>`.
    ///   - activity: Tracks the last time the run subprocess produced output.
    ///   - idleTimeout: Max seconds of no output (while not running) before failing.
    ///   - maxWait: Absolute ceiling on the wait, regardless of ongoing output.
    ///   - interval: How often to poll (in seconds).
    private func waitUntilServiceStarted(
        _ serviceName: String,
        activity: ActivityClock,
        foregroundRun: ForegroundRunHandle? = nil,
        idleTimeout: TimeInterval = 30,
        maxWait: TimeInterval = 300,
        interval: TimeInterval = 0.5
    ) async throws -> ServiceStartState {
        let containerName = containerName(for: serviceName)
        let client = ContainerClient()
        let start = Date()

        while true {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            let container = try? await client.get(id: containerName)
            if container?.status == .running {
                return .running
            }
            if container?.status == .stopped {
                if let foregroundRun {
                    // Attached (non-detached) run. The daemon reports `.stopped`
                    // throughout image/kernel fetch and only flips to `.running`
                    // once init starts, so only treat `.stopped` as terminal once
                    // the `container run` subprocess has actually exited. While it
                    // is still alive the container is still starting — fall through
                    // to the timeout checks and keep polling for `.running`.
                    if let code = await foregroundRun.exitCodeIfCompleted() {
                        try Self.validateStoppedServiceExitCode(code, serviceName: serviceName)
                        return .completed
                    }
                } else {
                    // Detached run: `container run -d` returns only after start, so
                    // by the time we observe `.stopped` the container has run and
                    // exited. Recover its exit code via the registry (registered
                    // while the runtime client was still alive) or `containerWait`.
                    let exitCode: Int32
                    if let exitCodeTask = await ServiceExitCodeRegistry.shared.task(for: containerName) {
                        exitCode = try await exitCodeTask.value
                        await ServiceExitCodeRegistry.shared.remove(for: containerName)
                    } else {
                        exitCode = try await Self.waitForInitExitCode(containerName: containerName)
                    }
                    try Self.validateStoppedServiceExitCode(exitCode, serviceName: serviceName)
                    return .completed
                }
            }
            let now = Date()
            // An active pull keeps refreshing `activity`, pushing the idle
            // deadline out, so slow downloads never trip this — only genuine
            // silence does.
            if now.timeIntervalSince(activity.lastActivity) > idleTimeout {
                throw NSError(
                    domain: "ContainerWait", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Timed out waiting for container '\(containerName)' to be running."
                    ])
            }
            // Absolute backstop: even with continuous output, never wait past
            // `maxWait` for the container to come up.
            if now.timeIntervalSince(start) > maxWait {
                throw NSError(
                    domain: "ContainerWait", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Timed out waiting for container '\(containerName)' to be running (exceeded \(Int(maxWait))s)."
                    ])
            }
        }


        throw NSError(
            domain: "ContainerWait", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Timed out waiting for container '\(containerName)' to start."
            ])
    }

    private static func waitForInitExitCode(containerName: String) async throws -> Int32 {
        let request = XPCMessage(route: .containerWait)
        request.set(key: .id, value: containerName)
        request.set(key: .processIdentifier, value: containerName)

        let client = XPCClient(service: "com.apple.container.apiserver")
        let response = try await client.send(request, responseTimeout: .seconds(10))
        return Int32(response.int64(key: .exitCode))
    }

    /// Stops (and optionally removes) containers matching the given names.
    /// Accepts pre-computed name strings so callers can pass all candidate
    /// shapes (legacy dashed, dotted DNS, explicit `container_name`) and
    /// teardown works regardless of which mode created them.
    private func stopExistingContainers(_ names: [String], remove: Bool) async throws {
        for container in names {
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
        if !dnsAvailable {
            await crossPatchHostsForService(serviceName)
        }
    }

    /// Apple `container` does not provide built-in DNS resolution between containers
    /// on the same network. As each service comes up, mutate /etc/hosts in every
    /// already-running peer to add `<thisIP> <thisService>`, and also add all the
    /// previously-known peers into the new container. This is best-effort — services
    /// that need DNS at startup time should still wait/retry.
    private func crossPatchHostsForService(_ newServiceName: String) async {
        guard let newIP = containerIps[newServiceName] else { return }
        let newContainerID = containerName(for: newServiceName)
        // Add the new entry in every previously-running peer.
        for (peerName, peerIP) in containerIps where peerName != newServiceName {
            let peerContainerID = containerName(for: peerName)
            await appendHostsEntry(in: peerContainerID, name: newServiceName, ip: newIP)
            // Also make the new container aware of this peer, in case it queries it later.
            await appendHostsEntry(in: newContainerID, name: peerName, ip: peerIP)
        }
    }

    private func appendHostsEntry(in containerID: String, name: String, ip: String) async {
        // Idempotent: skip if the line is already present. Use the `container` CLI
        // because the streaming exec API is not exposed here.
        let line = "\(ip) \(name)"
        let cmd = "grep -qF '\(line)' /etc/hosts 2>/dev/null || echo '\(line)' >> /etc/hosts"
        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = ["container", "exec", containerID, "sh", "-c", cmd]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run() } catch { return }
        process.waitUntilExit()
    }

    private func createVolume(name volumeName: String, config volumeConfig: Volume) async throws {
        let actualVolumeName = composeNamedVolumeName(
            source: volumeName,
            projectName: projectName,
            volumeDefinition: volumeConfig
        )

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
        } else if dnsAvailable, let dnsDomain {
            // Apple's DNS convention: the container's resolvable name is the
            // `--name` itself, e.g. `db.<project>` (see apple/container #800).
            containerName = "\(serviceName).\(dnsDomain)"
        } else {
            // Default container name based on project and service name
            containerName = "\(projectName)-\(serviceName)"
        }
        serviceContainerNames[serviceName] = containerName
        runCommandArgs.append("--name")
        runCommandArgs.append(containerName)

        // When real DNS is available, point the container at the project's DNS
        // domain. The daemon writes `nameserver <gateway>` + `domain <dnsDomain>`
        // into /etc/resolv.conf, so libc resolves both `db.<dnsDomain>` and the
        // short `db` (via implicit search list) to the peer's address.
        if dnsAvailable, let dnsDomain {
            runCommandArgs.append(contentsOf: ["--dns-domain", dnsDomain])
        }

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
                let networkTranslation = Self.networkRunArg(
                    network: networkToConnect,
                    aliases: service.networkConfigurations?[network]?.aliases ?? [],
                    serviceName: serviceName,
                    environmentVariables: environmentVariables
                )
                runCommandArgs.append(networkTranslation.arg)
                if let warning = networkTranslation.warning {
                    print(warning)
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

        // Add extra_hosts entries. `container run` (verified against container CLI
        // 1.0.0) has no --add-host flag at all — passing one fails immediately with
        // "Error: Unknown option '--add-host'" — so entries are written to a hosts
        // file and bind-mounted over /etc/hosts instead.
        //
        // The special token `host-gateway` is resolved via `container network
        // inspect`, which reports the vmnet bridge gateway the container actually
        // uses to reach the host. `route -n get default` (the previous approach)
        // instead returns the Mac's LAN default-route gateway, which is a different
        // address whenever the machine's default route isn't the vmnet bridge (e.g.
        // any normal Wi-Fi/Ethernet setup) — so containers would gain an entry
        // pointing at the router, not the host.
        if let extraHosts = service.extra_hosts, !extraHosts.isEmpty {
            print(
                "Note: service '\(serviceName)' sets extra_hosts. Since 'container run' has no --add-host "
                    + "flag, /etc/hosts is generated from scratch and bind-mounted in, which replaces the "
                    + "daemon's own generated file wholesale (Docker's --add-host appends instead). The "
                    + "container's own hostname is re-added below so self-resolution keeps working, but any "
                    + "other daemon-managed entries are not preserved."
            )

            // Resolve variables first: needsGateway must inspect the resolved value,
            // otherwise an entry fully wrapped in a variable (e.g. "${HOST_ENTRY}"
            // expanding to "foo:host-gateway") is missed and hostGatewayIP is left
            // empty, silently producing "--add-host foo:" (now "foo:" in /etc/hosts).
            let resolvedEntries = extraHosts.map { resolveVariable($0, with: environmentVariables) }
            let needsGateway = resolvedEntries.contains { $0.hasSuffix(":host-gateway") }
            let resolvedNetworkName = service.networks?.first.map { resolveVariable($0, with: environmentVariables) } ?? "default"
            let hostGatewayIP = needsGateway ? Self.resolveHostGatewayIP(networkName: resolvedNetworkName) : ""

            var hostsFileLines = ["127.0.0.1 localhost", "::1 localhost"]
            var seenHostnames: Set<String> = ["localhost"]
            for resolved in resolvedEntries {
                let parts = resolved.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let hostname = parts[0]
                let ip = parts[1] == "host-gateway" ? hostGatewayIP : parts[1]
                hostsFileLines.append("\(ip) \(hostname)")
                seenHostnames.insert(hostname)
            }

            // Re-add the container's own hostname → 127.0.0.1, the entry Apple's
            // container daemon would normally generate itself, so anything inside
            // the container that resolves its own hostname still works. Skipped if
            // extra_hosts already defines that name explicitly, so an intentional
            // user override wins.
            let ownHostname = service.hostname.map { resolveVariable($0, with: environmentVariables) } ?? containerName
            if !seenHostnames.contains(ownHostname) {
                hostsFileLines.append("127.0.0.1 \(ownHostname)")
            }

            let hostsFilePath = Self.extraHostsFilePath(projectName: projectName, serviceName: serviceName)
            do {
                try (hostsFileLines.joined(separator: "\n") + "\n").write(toFile: hostsFilePath, atomically: true, encoding: .utf8)
                runCommandArgs.append(contentsOf: ["-v", "\(hostsFilePath):/etc/hosts"])
            } catch {
                print("Warning: could not write hosts file for service '\(serviceName)' extra_hosts at \(hostsFilePath): \(error.localizedDescription)")
            }
        }

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

        // Add resource limits.
        // `mem_limit` is the top-level shorthand; `deploy.resources.limits.memory` is
        // the structured form. Both map to `container run --memory`. `mem_limit` takes
        // precedence when both are set, matching Docker Compose CLI behaviour.
        if let cpus = service.deploy?.resources?.limits?.cpus {
            runCommandArgs.append(contentsOf: ["--cpus", cpus])
        }
        let effectiveMemoryLimit = service.mem_limit ?? service.deploy?.resources?.limits?.memory
        if let memory = effectiveMemoryLimit {
            let resolved = resolveVariable(memory, with: environmentVariables)
            let (memoryArg, didClamp) = Self.clampMemoryLimit(resolved)
            if didClamp {
                print("Note: Service '\(serviceName)' mem_limit '\(resolved)' is below Apple Container's 200 MiB minimum; clamping to \(memoryArg).")
            }
            runCommandArgs.append(contentsOf: ["--memory", memoryArg])
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

        // Tracks output from the run subprocess so the readiness wait below can
        // tell an in-progress image pull from a stuck container.
        let activity = ActivityClock()

        @Sendable
        func handleOutput(_ output: String) {
            activity.touch()
            print("\(serviceName): \(output)".applyingColor(selectedColor))
        }

        var foregroundRunHandle: ForegroundRunHandle? = nil
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
            let detachedContainerName = containerName
            await ServiceExitCodeRegistry.shared.set(Task {
                try await Self.waitForInitExitCode(containerName: detachedContainerName)
            }, for: detachedContainerName)
        } else {
            let runHandle = ForegroundRunHandle()
            foregroundRunHandle = runHandle
            Task { [self, selectedColor, activity, runHandle] in
                @Sendable
                func handleOutput(_ output: String) {
                    activity.touch()
                    print("\(serviceName): \(output)".applyingColor(selectedColor))
                }

                print("\nStarting service: \(serviceName)")
                print("Starting \(serviceName)")
                print("----------------------------------------\n")
                do {
                    let exitCode = try await streamCommand(
                        "container",
                        args: ["run"] + runCommandArgs,
                        onStdout: handleOutput,
                        onStderr: handleOutput
                    )
                    await runHandle.complete(exitCode)
                    if exitCode != 0 {
                        fputs("Error: Service '\(serviceName)' exited with status \(exitCode).\n", stderr)
                    }
                } catch {
                    await runHandle.complete(-1)
                    fputs("Error starting service '\(serviceName)': \(error)\n", stderr)
                }
            }
        }

        let startState = try await waitUntilServiceStarted(serviceName, activity: activity, foregroundRun: foregroundRunHandle)
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

// MARK: extra_hosts file management
extension ComposeUp {
    /// Deterministic path for the generated /etc/hosts bind-mount source for a
    /// given service (see the extra_hosts handling in `configService`). Reused
    /// (overwritten) across repeated `up` runs of the same service rather than
    /// accumulating a new file each time. `ComposeDown` removes it once the
    /// container it was mounted into is actually stopped — not `up`, since the
    /// file may still be bind-mounted into a running container.
    static func extraHostsFilePath(projectName: String, serviceName: String) -> String {
        NSTemporaryDirectory() + "container-compose-\(projectName)-\(serviceName)-hosts"
    }
}

// MARK: Host gateway resolution
extension ComposeUp {
    /// Resolves the `host-gateway` token to the IP containers actually use to reach
    /// the host, for translating `extra_hosts: ["hostname:host-gateway"]` into a
    /// concrete `/etc/hosts` entry (see the extra_hosts handling in `configService`).
    ///
    /// Queries `container network inspect <networkName>` for `status.ipv4Gateway` —
    /// the vmnet bridge gateway Apple's `container` runtime routes container→host
    /// traffic through. This is deliberately *not* `route -n get default`: that
    /// reports the Mac's LAN default-route gateway (the router), which is a
    /// different, unreachable-from-the-container address on any machine whose
    /// default route isn't the vmnet bridge itself — i.e. almost always.
    ///
    /// Falls back to parsing `route -n get default` (the previous, unreliable
    /// approach) only if the network can't be inspected, with a warning — better
    /// than nothing, but callers should treat it as a guess.
    static func resolveHostGatewayIP(networkName: String = "default") -> String {
        if let gateway = inspectNetworkGateway(networkName) {
            return gateway
        }

        print(
            "Warning: could not determine network '\(networkName)' gateway via 'container network inspect'; "
                + "falling back to the host's LAN default-route gateway, which may not be reachable from the container."
        )

        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = ["route", "-n", "get", "default"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run() } catch { return "host-gateway" }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "host-gateway" }
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                return trimmed.dropFirst("gateway:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return "host-gateway"
    }

    /// Runs `container network inspect <networkName>` and extracts `status.ipv4Gateway`.
    /// Returns `nil` on any failure (missing binary, non-zero exit, unexpected JSON shape).
    private static func inspectNetworkGateway(_ networkName: String) -> String? {
        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = ["container", "network", "inspect", networkName]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard
            let networks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let status = networks.first?["status"] as? [String: Any],
            let gateway = status["ipv4Gateway"] as? String,
            !gateway.isEmpty
        else {
            return nil
        }
        return gateway
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

            var childEnvironment = ProcessInfo.processInfo.environment
            childEnvironment["PATH"] = mergedExecutablePath(existing: childEnvironment["PATH"])
            process.environment = childEnvironment

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
