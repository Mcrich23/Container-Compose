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

/// Service `env_file` entry, including Docker Compose long-form object syntax.
public struct ServiceEnvFile: Codable, Hashable {
    /// File path to load.
    public let path: String

    /// Whether the env file is required.
    public let required: Bool?

    /// Optional file format such as `raw`.
    public let format: String?

    public init(path: String, required: Bool? = true, format: String? = nil) {
        self.path = path
        self.required = required
        self.format = format
    }

    enum CodingKeys: String, CodingKey {
        case path, required, format
    }

    public init(from decoder: Decoder) throws {
        if let path = try? decoder.singleValueContainer().decode(String.self) {
            self.init(path: path)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            path: try container.decode(String.self, forKey: .path),
            required: try container.decodeIfPresent(Bool.self, forKey: .required) ?? true,
            format: try container.decodeIfPresent(String.self, forKey: .format)
        )
    }
}
