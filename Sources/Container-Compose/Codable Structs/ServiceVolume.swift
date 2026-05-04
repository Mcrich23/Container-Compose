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

public struct ServiceVolume: Codable, Hashable {
    public let mount: String

    public init(_ mount: String) {
        self.mount = mount
    }

    public init(from decoder: Decoder) throws {
        let singleValue = try decoder.singleValueContainer()
        if let mount = try? singleValue.decode(String.self) {
            self.mount = mount
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? "volume"
        let source = try container.decodeIfPresent(String.self, forKey: .source)
        let target = try container.decode(String.self, forKey: .target)
        let readOnly = try container.decodeIfPresent(Bool.self, forKey: .read_only) ?? false
        let consistency = try container.decodeIfPresent(String.self, forKey: .consistency)

        var options: [String] = []
        if readOnly {
            options.append("ro")
        }
        if let consistency, !consistency.isEmpty {
            options.append(consistency)
        }
        let suffix = options.isEmpty ? "" : ":\(options.joined(separator: ","))"

        switch type {
        case "bind":
            guard let source, !source.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .source,
                    in: container,
                    debugDescription: "Bind volume must define 'source'."
                )
            }
            mount = "\(source):\(target)\(suffix)"
        case "volume":
            guard let source, !source.isEmpty else {
                guard options.isEmpty else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .source,
                        in: container,
                        debugDescription: "Anonymous volumes cannot express mount options in short syntax."
                    )
                }
                mount = target
                return
            }
            mount = "\(source):\(target)\(suffix)"
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported service volume type '\(type)'."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(mount)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case source
        case target
        case read_only
        case consistency
    }
}
