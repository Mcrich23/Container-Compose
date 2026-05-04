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
        let type = try container.decode(String.self, forKey: .type)
        let source = try container.decodeIfPresent(String.self, forKey: .source)
        let target = try container.decode(String.self, forKey: .target)
        let readOnly = try Self.decodeBool(container, forKey: .read_only) ?? false
        let consistency = try container.decodeIfPresent(String.self, forKey: .consistency)
        let bind = try container.decodeIfPresent(BindOptions.self, forKey: .bind)
        let volume = try container.decodeIfPresent(VolumeOptions.self, forKey: .volume)

        var options: [String] = []
        if readOnly {
            options.append("ro")
        }
        if let selinux = bind?.selinux, !selinux.isEmpty {
            options.append(selinux)
        }
        if let propagation = bind?.propagation, !propagation.isEmpty {
            options.append(propagation)
        }
        if let consistency, !consistency.isEmpty {
            options.append(consistency)
        }
        if volume?.nocopy == true {
            options.append("nocopy")
        }
        if !readOnly, !options.isEmpty {
            options.insert("rw", at: 0)
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
                debugDescription: "Unsupported service volume type '\(type)'. Only 'bind' and 'volume' can be represented as mount strings."
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
        case bind
        case volume
    }

    private struct BindOptions: Codable, Hashable {
        let selinux: String?
        let propagation: String?
    }

    private struct VolumeOptions: Decodable, Hashable {
        let nocopy: Bool?

        enum CodingKeys: String, CodingKey {
            case nocopy
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            nocopy = try ServiceVolume.decodeBool(container, forKey: .nocopy)
        }
    }

    private static func decodeBool<K>(_ container: KeyedDecodingContainer<K>, forKey key: K) throws -> Bool? where K: CodingKey {
        try container.decodeIfPresent(BoolOrString.self, forKey: key)?.value
    }

    private struct BoolOrString: Decodable {
        let value: Bool

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let bool = try? container.decode(Bool.self) {
                value = bool
                return
            }
            if let string = try? container.decode(String.self) {
                switch string.lowercased() {
                case "true":
                    value = true
                case "false":
                    value = false
                default:
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Expected 'true' or 'false'."
                    )
                }
                return
            }
            throw DecodingError.typeMismatch(
                Bool.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected a boolean or string.")
            )
        }
    }
}
