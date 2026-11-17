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

import Foundation

/// A service may be incomplete until its inherited fields are resolved. This
/// boundary model uses the runtime's concrete field types without prematurely
/// requiring an image or a complete build context.
struct ExtendsService: Codable {
    var extends: ExtendsReference?
    /// Docker image name
    var image: String?

    /// Build configuration if the service is built from a Dockerfile
    var build: ExtendsBuild?

    /// Deployment configuration (primarily for Swarm)
    var deploy: Deploy?

    /// Restart policy (e.g., 'unless-stopped', 'always')
    var restart: String?

    /// Time Compose waits for the container to stop before sending SIGKILL.
    var stop_grace_period: StopGracePeriod?

    /// Healthcheck configuration
    var healthcheck: ExtendsHealthcheck?

    /// List of volume mounts (e.g., "hostPath:containerPath", "namedVolume:/path")
    var volumes: [String]?

    /// Environment variables to set in the container
    var environment: [String: String]?

    /// List of .env files to load environment variables from
    var env_file: [String]?

    /// Port mappings (e.g., "hostPort:containerPort")
    var ports: [String]?

    /// Command to execute in the container, overriding the image's default
    var command: [String]?

    /// Services this service depends on (for startup order)
    var depends_on: [String]?

    /// Service dependency options keyed by dependency service name.
    var dependencyConditions: [String: ServiceDependency]?

    /// User or UID to run the container as
    var user: String?

    /// Explicit name for the container instance
    var container_name: String?

    /// User-defined labels applied to the container (e.g. `{ "foo": "bar" }`).
    /// Passed through as `--label key=value`; the `com.docker.compose.project` and
    /// `com.docker.compose.service` labels are additionally stamped by `ComposeUp`
    /// and take precedence over any user value for those keys.
    var labels: [String: String]?

    /// List of networks the service will connect to
    var networks: [String]?

    /// Service network options keyed by network name.
    var networkConfigurations: [String: ServiceNetwork]?

    /// Container hostname
    var hostname: String?

    /// Entrypoint to execute in the container, overriding the image's default
    var entrypoint: [String]?

    /// Run container in privileged mode
    var privileged: Bool?

    /// Mount container's root filesystem as read-only
    var read_only: Bool?

    /// Working directory inside the container
    var working_dir: String?

    /// Platform architecture for the service
    var platform: String?

    /// Service-specific config usage (primarily for Swarm)
    var configs: [ServiceConfig]?

    /// Service-specific secret usage (primarily for Swarm)
    var secrets: [ServiceSecret]?

    /// Keep STDIN open (-i flag for `container run`)
    var stdin_open: Bool?

    /// Allocate a pseudo-TTY (-t flag for `container run`)
    var tty: Bool?
    
    /// Memory limit shorthand (e.g., "512m", "1g") — top-level alternative to
    /// `deploy.resources.limits.memory`. Takes precedence when both are set.
    var mem_limit: String?

    /// Additional `/etc/hosts` entries injected into the container. Each entry is a
    /// `"hostname:IP"` string. The special token `host-gateway` resolves to the host
    /// machine's IP as seen from inside the container.
    var extra_hosts: [String]?

    /// Profile names that gate this service (per the Compose spec `profiles` key).
    /// A service with no profiles (nil/empty) is always eligible. A service with
    /// profiles is only eligible when at least one of them is active — unless the
    /// service is named explicitly on the command line, or is a dependency of an
    /// eligible service, both of which bypass the profile gate per the Compose spec.
    var profiles: [String]?

    enum CodingKeys: String, CodingKey {
        case extends
        case image, build, deploy, restart, stop_grace_period, healthcheck, volumes, environment, env_file, ports, command, depends_on, user,
             container_name, labels, networks, hostname, entrypoint, privileged, read_only, working_dir, configs, secrets, stdin_open, tty, platform,
             mem_limit, extra_hosts, profiles
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        extends = try container.decodeIfPresent(ExtendsReference.self, forKey: .extends)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        build = try container.decodeIfPresent(ExtendsBuild.self, forKey: .build)
        deploy = try container.decodeIfPresent(Deploy.self, forKey: .deploy)
        
        restart = try container.decodeIfPresent(String.self, forKey: .restart)
        stop_grace_period = try container.decodeIfPresent(StopGracePeriod.self, forKey: .stop_grace_period)
        healthcheck = try container.decodeIfPresent(ExtendsHealthcheck.self, forKey: .healthcheck)
        volumes = try container.decodeIfPresent([String].self, forKey: .volumes)

        // `environment:` accepts both forms per the Compose spec:
        //   environment:                          environment:
        //     KEY: value                            - KEY=value
        //     OTHER: value          equivalent       - OTHER=value
        //                                            - INHERIT_FROM_HOST
        // Try the map form first; fall back to list form.
        if let asMap = try? container.decodeIfPresent([String: String].self, forKey: .environment) {
            environment = asMap
        } else if let asList = try? container.decodeIfPresent([String].self, forKey: .environment) {
            environment = Service.parseEnvironmentList(asList)
        } else {
            environment = nil
        }

        // `env_file` accepts three forms per the Compose spec:
        //   env_file: path.env               → single string
        //   env_file: [path1.env, path2.env] → array of strings
        //   env_file:                         → array of {path:, required:?} dicts (Compose 2.x extended form)
        //     - path: optional.env
        //       required: false
        // Arrays may also mix plain strings and dict entries.
        // Missing optional files (required: false) are loaded silently as empty — loadEnvFile
        // already suppresses read errors, which is the correct behaviour for optional files.
        struct EnvFileEntry: Decodable {
            let path: String
            init(from decoder: Decoder) throws {
                if let s = try? decoder.singleValueContainer().decode(String.self) {
                    path = s
                } else {
                    enum Keys: String, CodingKey { case path }
                    let c = try decoder.container(keyedBy: Keys.self)
                    path = try c.decode(String.self, forKey: .path)
                }
            }
        }
        if let entries = try? container.decodeIfPresent([EnvFileEntry].self, forKey: .env_file) {
            env_file = entries.map(\.path)
        } else if let single = try? container.decodeIfPresent(String.self, forKey: .env_file) {
            env_file = [single]
        } else {
            env_file = nil
        }

        ports = try container.decodeIfPresent([String].self, forKey: .ports)

        // Decode 'command' which can be either a single string or an array of strings.
        if let cmdArray = try? container.decodeIfPresent([String].self, forKey: .command) {
            command = cmdArray
        } else if let cmdString = try? container.decodeIfPresent(String.self, forKey: .command) {
            command = [cmdString]
        } else {
            command = nil
        }
        
        if let dependsOnString = try? container.decodeIfPresent(String.self, forKey: .depends_on) {
            depends_on = [dependsOnString]
            dependencyConditions = [dependsOnString: ServiceDependency()]
        } else if let dependsOnArray = try? container.decodeIfPresent([String].self, forKey: .depends_on) {
            depends_on = dependsOnArray
            dependencyConditions = Dictionary(uniqueKeysWithValues: dependsOnArray.map { ($0, ServiceDependency()) })
        } else if let dependsOnMap = try? container.decodeIfPresent([String: ServiceDependency?].self, forKey: .depends_on) {
            let normalized = dependsOnMap.mapValues { $0 ?? ServiceDependency() }
            depends_on = normalized.keys.sorted()
            dependencyConditions = normalized
        } else {
            depends_on = nil
            dependencyConditions = nil
        }
        user = try container.decodeIfPresent(String.self, forKey: .user)

        container_name = try container.decodeIfPresent(String.self, forKey: .container_name)
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels)
        if let networkArray = try? container.decodeIfPresent([String].self, forKey: .networks) {
            networks = networkArray
            networkConfigurations = Dictionary(uniqueKeysWithValues: networkArray.map { ($0, ServiceNetwork()) })
        } else if let networkMap = try? container.decodeIfPresent([String: ServiceNetwork?].self, forKey: .networks) {
            let normalized = networkMap.mapValues { $0 ?? ServiceNetwork() }
            networks = normalized.keys.sorted()
            networkConfigurations = normalized
        } else {
            networks = nil
            networkConfigurations = nil
        }
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
        
        // Decode 'entrypoint' which can be either a single string or an array of strings.
        if let entrypointArray = try? container.decodeIfPresent([String].self, forKey: .entrypoint) {
            entrypoint = entrypointArray
        } else if let entrypointString = try? container.decodeIfPresent(String.self, forKey: .entrypoint) {
            entrypoint = [entrypointString]
        } else {
            entrypoint = nil
        }

        privileged = try container.decodeIfPresent(Bool.self, forKey: .privileged)
        read_only = try container.decodeIfPresent(Bool.self, forKey: .read_only)
        working_dir = try container.decodeIfPresent(String.self, forKey: .working_dir)
        configs = try container.decodeIfPresent([ServiceConfig].self, forKey: .configs)
        secrets = try container.decodeIfPresent([ServiceSecret].self, forKey: .secrets)
        stdin_open = try container.decodeIfPresent(Bool.self, forKey: .stdin_open)
        tty = try container.decodeIfPresent(Bool.self, forKey: .tty)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        if let s = try? container.decodeIfPresent(String.self, forKey: .mem_limit) {
            mem_limit = s
        } else if let i = try? container.decodeIfPresent(Int.self, forKey: .mem_limit) {
            mem_limit = "\(i)"
        } else {
            mem_limit = nil
        }

        // `extra_hosts` accepts two forms per the Compose spec:
        //   extra_hosts:               extra_hosts:
        //     - "hostname:IP"    or      hostname: IP
        //     - "other:host-gateway"
        // The list form is most common; the map form is normalised to list form here.
        if let list = try? container.decodeIfPresent([String].self, forKey: .extra_hosts) {
            extra_hosts = list
        } else if let map = try? container.decodeIfPresent([String: String].self, forKey: .extra_hosts) {
            extra_hosts = map.map { "\($0.key):\($0.value)" }
        } else {
            extra_hosts = nil
        }

        // `profiles` is a plain list of strings per the Compose spec (no shorthand
        // single-string form).
        profiles = try container.decodeIfPresent([String].self, forKey: .profiles)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(build, forKey: .build)
        try container.encodeIfPresent(deploy, forKey: .deploy)
        try container.encodeIfPresent(restart, forKey: .restart)
        try container.encodeIfPresent(stop_grace_period, forKey: .stop_grace_period)
        try container.encodeIfPresent(healthcheck, forKey: .healthcheck)
        try container.encodeIfPresent(volumes, forKey: .volumes)
        try container.encodeIfPresent(environment, forKey: .environment)
        try container.encodeIfPresent(env_file, forKey: .env_file)
        try container.encodeIfPresent(ports, forKey: .ports)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(dependencyConditions, forKey: .depends_on)
        try container.encodeIfPresent(user, forKey: .user)
        try container.encodeIfPresent(container_name, forKey: .container_name)
        try container.encodeIfPresent(labels, forKey: .labels)
        try container.encodeIfPresent(networkConfigurations, forKey: .networks)
        try container.encodeIfPresent(hostname, forKey: .hostname)
        try container.encodeIfPresent(entrypoint, forKey: .entrypoint)
        try container.encodeIfPresent(privileged, forKey: .privileged)
        try container.encodeIfPresent(read_only, forKey: .read_only)
        try container.encodeIfPresent(working_dir, forKey: .working_dir)
        try container.encodeIfPresent(platform, forKey: .platform)
        try container.encodeIfPresent(configs, forKey: .configs)
        try container.encodeIfPresent(secrets, forKey: .secrets)
        try container.encodeIfPresent(stdin_open, forKey: .stdin_open)
        try container.encodeIfPresent(tty, forKey: .tty)
        try container.encodeIfPresent(mem_limit, forKey: .mem_limit)
        try container.encodeIfPresent(extra_hosts, forKey: .extra_hosts)
        try container.encodeIfPresent(profiles, forKey: .profiles)
    }
}

struct ExtendsReference: Codable {
    let service: String
    let file: String?

    init(from decoder: Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            service = name
            file = nil
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            service = try container.decode(String.self, forKey: .service)
            file = try container.decodeIfPresent(String.self, forKey: .file)
        }
        guard !service.isEmpty, file?.isEmpty != true else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "An extends reference needs a service name and a nonempty file path."))
        }
    }

    enum CodingKeys: String, CodingKey { case service, file }
}

struct ExtendsBuild: Codable {
    var context: String?
    var dockerfile: String?
    var args: [String: String]?

    init(from decoder: Decoder) throws {
        if let shorthand = try? decoder.singleValueContainer().decode(String.self) {
            context = shorthand
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            context = try container.decodeIfPresent(String.self, forKey: .context)
            dockerfile = try container.decodeIfPresent(String.self, forKey: .dockerfile)
            args = try container.decodeIfPresent([String: String].self, forKey: .args)
        }
    }

    enum CodingKeys: String, CodingKey { case context, dockerfile, args }

    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.context = context ?? parent.context
        result.dockerfile = dockerfile ?? parent.dockerfile
        result.args = mergedMapping(parent.args, args)
        return result
    }
}

struct ExtendsHealthcheck: Codable {
    var test: [String]?
    var start_period: String?
    var interval: String?
    var retries: Int?
    var timeout: String?
    var disable: Bool?

    init(from decoder: Decoder) throws {
        let healthcheck = try Healthcheck(from: decoder)
        test = healthcheck.test
        start_period = healthcheck.start_period
        interval = healthcheck.interval
        retries = healthcheck.retries
        timeout = healthcheck.timeout
        let container = try decoder.container(keyedBy: CodingKeys.self)
        disable = try container.decodeIfPresent(Bool.self, forKey: .disable)
    }

    enum CodingKeys: String, CodingKey { case test, start_period, interval, retries, timeout, disable }

    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.test = test ?? parent.test
        result.start_period = start_period ?? parent.start_period
        result.interval = interval ?? parent.interval
        result.retries = retries ?? parent.retries
        result.timeout = timeout ?? parent.timeout
        result.disable = disable ?? parent.disable
        return result
    }
}

private func mergedMapping<Value>(_ parent: [String: Value]?, _ child: [String: Value]?) -> [String: Value]? {
    guard let parent else { return child }
    guard let child else { return parent }
    return parent.merging(child) { _, child in child }
}

private func mergedSequence<Value: Equatable>(_ parent: [Value]?, _ child: [Value]?) -> [Value]? {
    guard let parent else { return child }
    guard let child else { return parent }
    return parent + child.filter { !parent.contains($0) }
}

extension ExtendsService {
    func inheriting(_ parent: Self) -> Self {
        var result = self

        result.image = image ?? parent.image
        result.restart = restart ?? parent.restart
        result.stop_grace_period = stop_grace_period ?? parent.stop_grace_period
        result.command = command ?? parent.command
        result.user = user ?? parent.user
        result.container_name = container_name ?? parent.container_name
        result.hostname = hostname ?? parent.hostname
        result.entrypoint = entrypoint ?? parent.entrypoint
        result.privileged = privileged ?? parent.privileged
        result.read_only = read_only ?? parent.read_only
        result.working_dir = working_dir ?? parent.working_dir
        result.platform = platform ?? parent.platform
        result.stdin_open = stdin_open ?? parent.stdin_open
        result.tty = tty ?? parent.tty
        result.mem_limit = mem_limit ?? parent.mem_limit
        result.profiles = profiles ?? parent.profiles
        result.extends = nil
        result.build = build?.inheriting(parent.build) ?? parent.build
        result.healthcheck = healthcheck?.inheriting(parent.healthcheck) ?? parent.healthcheck
        if let deploy, let inherited = parent.deploy {
            result.deploy = Deploy(inheriting: inherited, child: deploy)
        } else {
            result.deploy = deploy ?? parent.deploy
        }
        result.environment = mergedMapping(parent.environment, environment)
        result.labels = mergedMapping(parent.labels, labels)
        result.dependencyConditions = dependencyConditions ?? parent.dependencyConditions
        result.depends_on = depends_on ?? parent.depends_on
        result.networkConfigurations = networkConfigurations ?? parent.networkConfigurations
        result.networks = networks ?? parent.networks
        result.ports = mergedSequence(parent.ports, ports)
        result.configs = mergedSequence(parent.configs, configs)
        result.secrets = mergedSequence(parent.secrets, secrets)
        result.env_file = parent.env_file.map { $0 + (env_file ?? []) } ?? env_file
        result.extra_hosts = mergedHosts(parent.extra_hosts, extra_hosts)
        if let volumes {
            var inherited = parent.volumes ?? []
            for volume in volumes {
                if let index = inherited.firstIndex(where: { Self.volumeTarget($0) == Self.volumeTarget(volume) }) {
                    inherited[index] = volume
                } else {
                    inherited.append(volume)
                }
            }
            result.volumes = inherited
        } else {
            result.volumes = parent.volumes
        }
        return result
    }

    private static func volumeTarget(_ specification: String) -> String {
        let parts = specification.split(separator: ":", omittingEmptySubsequences: false)
        return String(parts.count > 1 ? parts[1] : parts[0])
    }
}

private func mergedHosts(_ parent: [String]?, _ child: [String]?) -> [String]? {
    guard let parent else { return child }
    guard let child else { return parent }
    var result = parent
    for entry in child {
        let name = entry.split(separator: ":", maxSplits: 1).first
        if let index = result.firstIndex(where: { $0.split(separator: ":", maxSplits: 1).first == name }) {
            result[index] = entry
        } else {
            result.append(entry)
        }
    }
    return result
}

extension Deploy {
    init(inheriting parent: Self, child: Self) {
        mode = child.mode ?? parent.mode
        replicas = child.replicas ?? (child.replicasExpression == nil ? parent.replicas : nil)
        replicasExpression = child.replicasExpression ?? (child.replicas == nil ? parent.replicasExpression : nil)
        if let base = parent.resources, let override = child.resources {
            let limits: ResourceLimits?
            if let base = base.limits, let override = override.limits {
                limits = ResourceLimits(cpus: override.cpus ?? base.cpus, memory: override.memory ?? base.memory)
            } else {
                limits = override.limits ?? base.limits
            }
            resources = DeployResources(limits: limits, reservations: override.reservations ?? base.reservations)
        } else {
            resources = child.resources ?? parent.resources
        }
        if let base = parent.restart_policy, let override = child.restart_policy {
            restart_policy = DeployRestartPolicy(condition: override.condition ?? base.condition, delay: override.delay ?? base.delay,
                                                 max_attempts: override.max_attempts ?? base.max_attempts, window: override.window ?? base.window)
        } else {
            restart_policy = child.restart_policy ?? parent.restart_policy
        }
    }
}
