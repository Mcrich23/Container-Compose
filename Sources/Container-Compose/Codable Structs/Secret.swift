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
//  Secret.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Represents a top-level secret definition (primarily for Swarm).
public struct Secret: Codable {
    /// Path to the file containing the secret content
    public let file: String?
    /// Environment variable to populate with the secret content
    public let environment: String?
    /// Indicates if the secret is external (pre-existing)
    public let external: ExternalSecret?
    /// Explicit name for the secret
    public let name: String?
    /// Labels for the secret
    public let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case file, environment, external, name, labels
    }

    /// Custom initializer to handle `external: true` (boolean) or `external: { name: "my_sec" }` (object).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        file = try container.decodeIfPresent(String.self, forKey: .file)
        environment = try container.decodeIfPresent(String.self, forKey: .environment)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels)

        if try !container.contains(.external) || container.decodeNil(forKey: .external) {
            external = nil
        } else if let value = try? container.decode(Bool.self, forKey: .external) {
            external = ExternalSecret(isExternal: value, name: nil)
        } else {
            let value = try container.decode([String: String].self, forKey: .external)
            guard value.count == 1, let externalName = value["name"], !externalName.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .external, in: container,
                    debugDescription: "external must be a boolean or a mapping containing only a nonempty name")
            }
            external = ExternalSecret(isExternal: true, name: externalName)
        }
    }
}
