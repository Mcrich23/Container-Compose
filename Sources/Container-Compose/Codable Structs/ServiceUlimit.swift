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

/// Docker Compose `ulimits` entry, preserving both scalar and soft/hard forms.
public struct ServiceUlimit: Codable, Hashable {
    public let value: String?
    public let soft: String?
    public let hard: String?

    public init(value: String? = nil, soft: String? = nil, hard: String? = nil) {
        self.value = value
        self.soft = soft
        self.hard = hard
    }

    enum CodingKeys: String, CodingKey {
        case value, soft, hard
    }

    public init(from decoder: Decoder) throws {
        if let intValue = try? decoder.singleValueContainer().decode(Int.self) {
            self.init(value: String(intValue))
            return
        }
        if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
            self.init(value: stringValue)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let soft = try Self.decodeScalar(container, forKey: .soft)
        let hard = try Self.decodeScalar(container, forKey: .hard)
        guard soft != nil, hard != nil else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Ulimit object entries must include both 'soft' and 'hard'.")
            )
        }
        self.init(soft: soft, hard: hard)
    }

    private static func decodeScalar(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> String? {
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }
        return try container.decodeIfPresent(String.self, forKey: key)
    }
}
