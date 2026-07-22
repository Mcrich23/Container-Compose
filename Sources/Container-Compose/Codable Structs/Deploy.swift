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
//  Deploy.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//

import Foundation


/// Represents the `deploy` configuration for a service (primarily for Swarm orchestration).
public struct Deploy: Codable, Hashable {
    /// Deployment mode (e.g., 'replicated', 'global')
    public let mode: String?
    /// Number of replicated service tasks
    public let replicas: Int?
    /// Raw non-numeric replicas expression, such as an env-var placeholder
    public let replicasExpression: String?
    /// Resource constraints (limits, reservations)
    public let resources: DeployResources?
    /// Restart policy for tasks
    public let restart_policy: DeployRestartPolicy?

    enum CodingKeys: String, CodingKey {
        case mode, replicas, resources, restart_policy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        resources = try container.decodeIfPresent(DeployResources.self, forKey: .resources)
        restart_policy = try container.decodeIfPresent(DeployRestartPolicy.self, forKey: .restart_policy)

        do {
            replicas = try container.decodeIfPresent(Int.self, forKey: .replicas)
            replicasExpression = nil
        } catch {
            let rawReplicas = try container.decode(String.self, forKey: .replicas)
            let normalizedReplicas = Self.normalizedReplicasExpression(rawReplicas)

            if let parsedReplicas = Int(normalizedReplicas) {
                replicas = parsedReplicas
                replicasExpression = nil
            } else {
                replicas = nil
                replicasExpression = normalizedReplicas
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(mode, forKey: .mode)
        if let replicas {
            try container.encode(replicas, forKey: .replicas)
        } else {
            try container.encodeIfPresent(replicasExpression, forKey: .replicas)
        }
        try container.encodeIfPresent(resources, forKey: .resources)
        try container.encodeIfPresent(restart_policy, forKey: .restart_policy)
    }

    private static func normalizedReplicasExpression(_ value: String) -> String {
        var normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedValue.count >= 2 else { return normalizedValue }

        let firstCharacter = normalizedValue.first
        let lastCharacter = normalizedValue.last
        if (firstCharacter == "\"" && lastCharacter == "\"") || (firstCharacter == "'" && lastCharacter == "'") {
            normalizedValue = String(normalizedValue.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return normalizedValue
    }
}
