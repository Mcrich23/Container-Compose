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
//  Service.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//

import Foundation


/// Represents a single service definition within the `services` section.
public struct Service: Codable, Hashable {
    /// Docker image name
    public let image: String?

    /// Build configuration if the service is built from a Dockerfile
    public let build: Build?

    /// Deployment configuration (primarily for Swarm)
    public let deploy: Deploy?

    /// Restart policy (e.g., 'unless-stopped', 'always')
    public let restart: String?

    /// Healthcheck configuration
    public let healthcheck: Healthcheck?

    /// List of volume mounts (e.g., "hostPath:containerPath", "namedVolume:/path")
    public let volumes: [String]?

    /// Environment variables to set in the container
    public let environment: [String: String]?

    /// List of .env files to load environment variables from
    public let env_file: [String]?

    /// Detailed env file entries keyed by list order
    public let envFileConfigurations: [ServiceEnvFile]?

    /// Port mappings (e.g., "hostPort:containerPort")
    public let ports: [String]?

    /// Command to execute in the container, overriding the image's default
    public let command: [String]?

    /// Services this service depends on (for startup order)
    public let depends_on: [String]?

    /// Detailed dependency options keyed by service name
    public let dependencyConfigurations: [String: ServiceDependency]?

    /// User or UID to run the container as
    public let user: String?

    /// Explicit name for the container instance
    public let container_name: String?

    /// List of networks the service will connect to
    public let networks: [String]?

    /// Service-level network options keyed by network name
    public let networkConfigurations: [String: ServiceNetwork]?

    /// Container hostname
    public let hostname: String?

    /// Entrypoint to execute in the container, overriding the image's default
    public let entrypoint: [String]?

    /// Run container in privileged mode
    public let privileged: Bool?

    /// Mount container's root filesystem as read-only
    public let read_only: Bool?

    /// Mount tmpfs paths inside the container
    public let tmpfs: [String]?

    /// Linux capabilities to add
    public let cap_add: [String]?

    /// Linux capabilities to drop
    public let cap_drop: [String]?

    /// Container ulimit settings
    public let ulimits: [String: ServiceUlimit]?

    /// Run an init process as PID 1
    public let initProcess: Bool?

    /// Security options such as no-new-privileges
    public let security_opt: [String]?

    /// Working directory inside the container
    public let working_dir: String?

    /// Platform architecture for the service
    public let platform: String?

    /// Profiles that activate this service
    public let profiles: [String]?

    /// Service-specific config usage (primarily for Swarm)
    public let configs: [ServiceConfig]?

    /// Service-specific secret usage (primarily for Swarm)
    public let secrets: [ServiceSecret]?

    /// Keep STDIN open (-i flag for `container run`)
    public let stdin_open: Bool?

    /// Allocate a pseudo-TTY (-t flag for `container run`)
    public let tty: Bool?
    
    /// Other services that depend on this service
    public var dependedBy: [String] = []
    
    // Defines custom coding keys to map YAML keys to Swift properties
    enum CodingKeys: String, CodingKey {
        case image, build, deploy, restart, healthcheck, volumes, environment, env_file, ports, command, depends_on, user,
             container_name, networks, hostname, entrypoint, privileged, read_only, tmpfs, cap_add, cap_drop, ulimits, initProcess = "init", security_opt, working_dir, configs, secrets, stdin_open, tty, platform, profiles
    }
    
    /// Public memberwise initializer for testing
    public init(
        image: String? = nil,
        build: Build? = nil,
        deploy: Deploy? = nil,
        restart: String? = nil,
        healthcheck: Healthcheck? = nil,
        volumes: [String]? = nil,
        environment: [String: String]? = nil,
        env_file: [String]? = nil,
        envFileConfigurations: [ServiceEnvFile]? = nil,
        ports: [String]? = nil,
        command: [String]? = nil,
        depends_on: [String]? = nil,
        dependencyConfigurations: [String: ServiceDependency]? = nil,
        user: String? = nil,
        container_name: String? = nil,
        networks: [String]? = nil,
        networkConfigurations: [String: ServiceNetwork]? = nil,
        hostname: String? = nil,
        entrypoint: [String]? = nil,
        privileged: Bool? = nil,
        read_only: Bool? = nil,
        tmpfs: [String]? = nil,
        cap_add: [String]? = nil,
        cap_drop: [String]? = nil,
        ulimits: [String: ServiceUlimit]? = nil,
        initProcess: Bool? = nil,
        security_opt: [String]? = nil,
        working_dir: String? = nil,
        platform: String? = nil,
        profiles: [String]? = nil,
        configs: [ServiceConfig]? = nil,
        secrets: [ServiceSecret]? = nil,
        stdin_open: Bool? = nil,
        tty: Bool? = nil,
        dependedBy: [String] = []
    ) {
        self.image = image
        self.build = build
        self.deploy = deploy
        self.restart = restart
        self.healthcheck = healthcheck
        self.volumes = volumes
        self.environment = environment
        self.env_file = env_file
        self.envFileConfigurations = envFileConfigurations
        self.ports = ports
        self.command = command
        self.depends_on = depends_on
        self.dependencyConfigurations = dependencyConfigurations
        self.user = user
        self.container_name = container_name
        self.networks = networks
        self.networkConfigurations = networkConfigurations
        self.hostname = hostname
        self.entrypoint = entrypoint
        self.privileged = privileged
        self.read_only = read_only
        self.tmpfs = tmpfs
        self.cap_add = cap_add
        self.cap_drop = cap_drop
        self.ulimits = ulimits
        self.initProcess = initProcess
        self.security_opt = security_opt
        self.working_dir = working_dir
        self.platform = platform
        self.profiles = profiles
        self.configs = configs
        self.secrets = secrets
        self.stdin_open = stdin_open
        self.tty = tty
        self.dependedBy = dependedBy
    }

    /// Custom initializer to handle decoding and basic validation.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        build = try container.decodeIfPresent(Build.self, forKey: .build)
        deploy = try container.decodeIfPresent(Deploy.self, forKey: .deploy)
        
        // Ensure that a service has either an image or a build context.
        guard image != nil || build != nil else {
            throw DecodingError.dataCorruptedError(forKey: .image, in: container, debugDescription: "Service must have either 'image' or 'build' specified.")
        }

        restart = try container.decodeIfPresent(String.self, forKey: .restart)
        healthcheck = try container.decodeIfPresent(Healthcheck.self, forKey: .healthcheck)
        volumes = try Self.decodeVolumeList(container, forKey: .volumes)
        environment = try Self.decodeEnvironment(container, forKey: .environment)
        if let envFile = try? container.decodeIfPresent(String.self, forKey: .env_file) {
            env_file = [envFile]
            envFileConfigurations = [ServiceEnvFile(path: envFile)]
        } else if let envFiles = try? container.decodeIfPresent([String].self, forKey: .env_file) {
            env_file = envFiles
            envFileConfigurations = envFiles.map { ServiceEnvFile(path: $0) }
        } else if let envFiles = try? container.decodeIfPresent([ServiceEnvFile].self, forKey: .env_file) {
            env_file = envFiles.map(\.path)
            envFileConfigurations = envFiles
        } else {
            env_file = nil
            envFileConfigurations = nil
        }
        ports = try container.decodeIfPresent([String].self, forKey: .ports)

        // Decode 'command' which can be either a single string or an array of strings.
        if let cmdArray = try? container.decodeIfPresent([String].self, forKey: .command) {
            command = cmdArray
        } else if let cmdString = try? container.decodeIfPresent(String.self, forKey: .command) {
            command = composeShellSplit(cmdString)
        } else {
            command = nil
        }
        
        if let dependsOnString = try? container.decodeIfPresent(String.self, forKey: .depends_on) {
            depends_on = [dependsOnString]
            dependencyConfigurations = [dependsOnString: ServiceDependency(condition: "service_started")]
        } else {
            if let dependencyList = try? container.decodeIfPresent([String].self, forKey: .depends_on) {
                depends_on = dependencyList
                dependencyConfigurations = Dictionary(uniqueKeysWithValues: dependencyList.map {
                    ($0, ServiceDependency(condition: "service_started"))
                })
            } else if let dependencyMap = try? container.decodeIfPresent([String: ServiceDependency].self, forKey: .depends_on) {
                depends_on = dependencyMap.keys.sorted()
                dependencyConfigurations = dependencyMap
            } else {
                depends_on = nil
                dependencyConfigurations = nil
            }
        }
        user = try container.decodeIfPresent(String.self, forKey: .user)

        container_name = try container.decodeIfPresent(String.self, forKey: .container_name)
        if let networkList = try? container.decodeIfPresent([String].self, forKey: .networks) {
            networks = networkList
            networkConfigurations = Dictionary(uniqueKeysWithValues: networkList.map {
                ($0, ServiceNetwork())
            })
        } else if let networkMap = try? container.decodeIfPresent([String: ServiceNetwork?].self, forKey: .networks) {
            networks = networkMap.keys.sorted()
            networkConfigurations = networkMap.mapValues { $0 ?? ServiceNetwork() }
        } else {
            networks = nil
            networkConfigurations = nil
        }
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
        
        // Decode 'entrypoint' which can be either a single string or an array of strings.
        if let entrypointArray = try? container.decodeIfPresent([String].self, forKey: .entrypoint) {
            entrypoint = entrypointArray
        } else if let entrypointString = try? container.decodeIfPresent(String.self, forKey: .entrypoint) {
            entrypoint = composeShellSplit(entrypointString)
        } else {
            entrypoint = nil
        }

        privileged = try container.decodeIfPresent(Bool.self, forKey: .privileged)
        read_only = try container.decodeIfPresent(Bool.self, forKey: .read_only)
        tmpfs = try Self.decodeStringList(container, forKey: .tmpfs)
        cap_add = try Self.decodeStringList(container, forKey: .cap_add)
        cap_drop = try Self.decodeStringList(container, forKey: .cap_drop)
        ulimits = try container.decodeIfPresent([String: ServiceUlimit].self, forKey: .ulimits)
        initProcess = try container.decodeIfPresent(Bool.self, forKey: .initProcess)
        security_opt = try Self.decodeStringList(container, forKey: .security_opt)
        working_dir = try container.decodeIfPresent(String.self, forKey: .working_dir)
        configs = try container.decodeIfPresent([ServiceConfig].self, forKey: .configs)
        secrets = try container.decodeIfPresent([ServiceSecret].self, forKey: .secrets)
        stdin_open = try container.decodeIfPresent(Bool.self, forKey: .stdin_open)
        tty = try container.decodeIfPresent(Bool.self, forKey: .tty)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        if let profile = try? container.decodeIfPresent(String.self, forKey: .profiles) {
            profiles = [profile]
        } else {
            profiles = try container.decodeIfPresent([String].self, forKey: .profiles)
        }
    }

    private static func decodeStringList(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> [String]? {
        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return [string]
        }
        return try container.decodeIfPresent([String].self, forKey: key)
    }

    private static func decodeEnvironment(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> [String: String]? {
        guard container.contains(key) else { return nil }
        if let mapping = try? container.decode([String: String].self, forKey: key) {
            return mapping
        }
        let entries = try container.decode([String].self, forKey: key)
        var environment: [String: String] = [:]
        for entry in entries {
            let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                environment[String(parts[0])] = String(parts[1])
            } else if let value = ProcessInfo.processInfo.environment[entry] {
                environment[entry] = value
            }
        }
        return environment
    }

    private static func decodeVolumeList(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> [String]? {
        guard container.contains(key) else { return nil }
        let volumes = try container.decode([ServiceVolume].self, forKey: key)
        return volumes.map(\.mount)
    }
    
    /// Returns the services in topological order based on `depends_on` relationships.
    public static func topoSortConfiguredServices(
        _ services: [(serviceName: String, service: Service)]
    ) throws -> [(serviceName: String, service: Service)] {
        
        var visited = Set<String>()
        var visiting = Set<String>()
        var sorted: [(String, Service)] = []

        func visit(_ name: String, from service: String? = nil) throws {
            guard var serviceTuple = services.first(where: { $0.serviceName == name }) else { return }
            if let service {
                serviceTuple.service.dependedBy.append(service)
            }
            
            if visiting.contains(name) {
                throw NSError(domain: "ComposeError", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Cyclic dependency detected involving '\(name)'"
                ])
            }
            guard !visited.contains(name) else { return }

            visiting.insert(name)
            for depName in serviceTuple.service.depends_on ?? [] {
                try visit(depName, from: name)
            }
            visiting.remove(name)
            visited.insert(name)
            sorted.append(serviceTuple)
        }

        for (serviceName, _) in services {
            if !visited.contains(serviceName) {
                try visit(serviceName)
            }
        }

        return sorted
    }
}
