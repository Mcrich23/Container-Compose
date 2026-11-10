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

/// A single `ulimits:` entry from a Compose service, e.g.
///
///     ulimits:
///       nofile: 65535
///       nproc:
///         soft: 1024
///         hard: 2048
///
/// Values may be bare integers, numeric strings, or a `{soft, hard}` mapping.
/// Stored as strings so unresolved environment-variable expressions survive
/// decoding and can be resolved (and passed through to `--ulimit`) later.
public struct Ulimit: Codable, Hashable {
    public let soft: String?
    public let hard: String?

    enum CodingKeys: String, CodingKey {
        case soft, hard
    }

    public init(soft: String? = nil, hard: String? = nil) {
        self.soft = soft
        self.hard = hard
    }

    public init(from decoder: Decoder) throws {
        // Short form: `nofile: 65535` (or "65535") — soft and hard are equal.
        let single = try decoder.singleValueContainer()
        if let value = Self.decodeScalar(from: single) {
            soft = value
            hard = value
            return
        }

        // Long form: `nofile: { soft: 1024, hard: 2048 }`.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        soft = Self.decodeScalar(container, forKey: .soft)
        hard = Self.decodeScalar(container, forKey: .hard)
        guard soft != nil || hard != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .soft,
                in: container,
                debugDescription: "ulimit entry must be a number, a string, or a {soft, hard} mapping."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        if soft == hard {
            var single = encoder.singleValueContainer()
            try single.encode(soft)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(soft, forKey: .soft)
        try container.encodeIfPresent(hard, forKey: .hard)
    }

    /// Decodes a scalar rlimit value, accepting numbers and numeric strings.
    private static func decodeScalar(from single: SingleValueDecodingContainer) -> String? {
        if let string = try? single.decode(String.self) {
            return string
        }
        if let int = try? single.decode(Int.self) {
            return "\(int)"
        }
        if let double = try? single.decode(Double.self) {
            return normalizedNumber(double)
        }
        return nil
    }

    private static func decodeScalar(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return string
        }
        if let int = try? container.decodeIfPresent(Int.self, forKey: key) {
            return "\(int)"
        }
        if let double = try? container.decodeIfPresent(Double.self, forKey: key) {
            return normalizedNumber(double)
        }
        return nil
    }

    private static func normalizedNumber(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        }
        return "\(value)"
    }
}
