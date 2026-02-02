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
//  DockerCompose.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//

/// Represents the top-level structure of a docker-compose.yml file.
public struct DockerCompose: Codable {
    /// The Compose file format version (e.g., '3.8')
    public let version: String?
    /// Optional project name
    public let name: String?
    /// Dictionary of service definitions, keyed by service name
    public let services: [String: Service?]
    /// Optional top-level volume definitions
    public let volumes: [String: Volume?]?
    /// Optional top-level network definitions
    public let networks: [String: Network?]?
    /// Optional top-level config definitions (primarily for Swarm)
    public let configs: [String: Config?]?
    /// Optional top-level secret definitions (primarily for Swarm)
    public let secrets: [String: Secret?]?
    /// Optional includes of other compose files
    public let includes: [DockerInclude]?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        services = try container.decode([String: Service?].self, forKey: .services)

        if let volumes = try container.decodeIfPresent([String: Volume?].self, forKey: .volumes) {
            let safeVolumes: [String: Volume] = volumes.mapValues { value in
                value ?? Volume()
            }
            self.volumes = safeVolumes
        } else {
            self.volumes = nil
        }
        networks = try container.decodeIfPresent([String: Network?].self, forKey: .networks)
        configs = try container.decodeIfPresent([String: Config?].self, forKey: .configs)
        secrets = try container.decodeIfPresent([String: Secret?].self, forKey: .secrets)
        includes = try container.decodeIfPresent([DockerInclude].self, forKey: .includes)
    }

    public init(
        version: String? = nil,
        name: String? = nil,
        services: [String: Service?],
        volumes: [String: Volume?]? = nil,
        networks: [String: Network?]? = nil,
        configs: [String: Config?]? = nil,
        secrets: [String: Secret?]? = nil,
        includes: [DockerInclude]? = nil
    ) {
        self.version = version
        self.name = name
        self.services = services
        self.volumes = volumes
        self.networks = networks
        self.configs = configs
        self.secrets = secrets
        self.includes = includes
    }

    /// Merges another DockerCompose into this one, with the other taking precedence in case of conflicts.
    /// - Parameter with: The DockerCompose to merge into this one.
    /// - Returns: A new DockerCompose instance representing the merged result.
    public func merge(with: DockerCompose) -> DockerCompose {
        // Merge services
        var mergedServices = self.services
        for (key, service) in with.services {
            mergedServices[key] = service
        }

        // Merge volumes
        var mergedVolumes = self.volumes ?? [:]
        if let withVolumes = with.volumes {
            for (key, volume) in withVolumes {
                mergedVolumes[key] = volume
            }
        }

        // Merge networks
        var mergedNetworks = self.networks ?? [:]
        if let withNetworks = with.networks {
            for (key, network) in withNetworks {
                mergedNetworks[key] = network
            }
        }

        return DockerCompose(
            version: with.version ?? self.version,
            name: with.name ?? self.name,
            services: mergedServices,
            volumes: mergedVolumes.isEmpty ? nil : mergedVolumes,
            networks: mergedNetworks.isEmpty ? nil : mergedNetworks,
            configs: with.configs ?? self.configs,
            secrets: with.secrets ?? self.secrets,
            includes: with.includes ?? self.includes
        )
    }
}

public struct DockerInclude: Codable {
    // The file to include
    let file: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        file = try container.decode(String.self, forKey: .file)
    }
}
