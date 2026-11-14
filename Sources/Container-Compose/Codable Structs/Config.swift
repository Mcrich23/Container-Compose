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
//  Config.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Represents a top-level config definition (primarily for Swarm).
public struct Config: Codable {
    /// Path to the file containing the config content
    public let file: String?
    /// Indicates if the config is external (pre-existing)
    public let external: ExternalConfig?
    /// Explicit name for the config
    public let name: String?
    /// Labels for the config
    public let labels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case file, external, name, labels
    }

    /// Custom initializer to handle `external: true` (boolean) or `external: { name: "my_cfg" }` (object).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        file = try container.decodeIfPresent(String.self, forKey: .file)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels)

        if try !container.contains(.external) || container.decodeNil(forKey: .external) {
            external = nil
        } else if let value = try? container.decode(Bool.self, forKey: .external) {
            external = ExternalConfig(isExternal: value, name: nil)
        } else {
            let value = try container.decode([String: String].self, forKey: .external)
            guard value.count == 1, let externalName = value["name"], !externalName.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .external, in: container,
                    debugDescription: "external must be a boolean or a mapping containing only a nonempty name")
            }
            external = ExternalConfig(isExternal: true, name: externalName)
        }
    }
}
