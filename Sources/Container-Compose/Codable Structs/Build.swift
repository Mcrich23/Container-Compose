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
//  Build.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Represents the `build` configuration for a service.
public struct Build: Codable, Hashable {
    /// Path to the build context, defaulting to the project directory when omitted.
    public let context: String
    /// Optional path to the Dockerfile within the context
    public let dockerfile: String?
    /// Build arguments
    public let args: [String: String?]?
    /// Optional target build stage, for multi-stage Dockerfiles
    public let target: String?

    /// Custom initializer to handle `build: .` (string) or `build: { context: . }` (object)
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let contextString = try? container.decode(String.self) {
            self.context = contextString
            self.dockerfile = nil
            self.args = nil
            self.target = nil
        } else {
            let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
            self.context = try keyedContainer.decodeIfPresent(String.self, forKey: .context) ?? "."
            self.dockerfile = try keyedContainer.decodeIfPresent(String.self, forKey: .dockerfile)
            if try !keyedContainer.contains(.args) || keyedContainer.decodeNil(forKey: .args) {
                self.args = nil
            } else if let entries = try? keyedContainer.decode([String].self, forKey: .args) {
                self.args = try parseBuildArgumentEntries(entries)
            } else {
                self.args = try keyedContainer.decode([String: String?].self, forKey: .args)
                for key in self.args?.keys ?? Dictionary<String, String?>().keys {
                    guard !key.isEmpty, !key.contains("=") else {
                        throw DecodingError.dataCorruptedError(forKey: .args, in: keyedContainer, debugDescription: "Invalid build argument name")
                    }
                }
            }
            self.target = try keyedContainer.decodeIfPresent(String.self, forKey: .target)
        }
    }

    enum CodingKeys: String, CodingKey {
        case context, dockerfile, args, target
    }
}

func parseBuildArgumentEntries(_ entries: [String]) throws -> [String: String?] {
    var result: [String: String?] = [:]
    for entry in entries {
        let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard !parts[0].isEmpty else {
            throw BuildArgumentError.invalidName
        }
        result.updateValue(parts.count == 2 ? String(parts[1]) : nil, forKey: String(parts[0]))
    }
    return result
}

enum BuildArgumentError: Error {
    case invalidName
}

/// Resolves inherited arguments after CLI overrides, omitting missing values so Dockerfile defaults apply.
func resolvedBuildArguments(_ file: [String: String?]?, cli: [String] = [], environment: [String: String]) throws -> [String: String] {
    let merged = (file ?? [:]).merging(try parseBuildArgumentEntries(cli)) { _, value in value }
    return merged.reduce(into: [:]) { result, entry in
        if let value = entry.value ?? environment[entry.key] {
            result[entry.key] = value
        }
    }
}
