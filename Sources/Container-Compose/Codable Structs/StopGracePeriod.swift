//===----------------------------------------------------------------------===//
// Copyright © 2025 Morris Richman and the Container-Compose project authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import Foundation

/// A Compose duration used for the time allowed for a container to stop.
public struct StopGracePeriod: Codable, Hashable, Sendable {
    /// Docker Compose's default when `stop_grace_period` is omitted.
    public static let defaultTimeoutInSeconds: Int32 = 10

    /// The duration as written in the Compose file.
    public let value: String

    /// The whole seconds accepted by Apple Container's stop API.
    ///
    /// Docker Compose also passes the duration to a whole-second runtime API,
    /// so fractional seconds are truncated rather than rounded up.
    public let timeoutInSeconds: Int32

    public init(_ value: String) throws {
        let seconds = try Self.parseSeconds(value)
        self.value = value
        self.timeoutInSeconds = Int32(seconds)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        try self.init(value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    private static func parseSeconds(_ value: String) throws -> Double {
        guard !value.isEmpty else { throw InvalidDurationError(value: value) }

        var index = value.startIndex
        var total: Double = 0
        var foundComponent = false

        while index < value.endIndex {
            let numberStart = index
            while index < value.endIndex, value[index].isNumber {
                index = value.index(after: index)
            }
            let hasIntegerDigits = index > numberStart
            var hasFractionDigits = false

            if index < value.endIndex, value[index] == "." {
                index = value.index(after: index)
                let fractionStart = index
                while index < value.endIndex, value[index].isNumber {
                    index = value.index(after: index)
                }
                hasFractionDigits = index > fractionStart
                guard hasFractionDigits else { throw InvalidDurationError(value: value) }
            }

            guard hasIntegerDigits || hasFractionDigits else {
                throw InvalidDurationError(value: value)
            }

            let number = String(value[numberStart..<index])
            guard let amount = Double(number), amount.isFinite else {
                throw InvalidDurationError(value: value)
            }

            let unit: String
            if value[index...].hasPrefix("ns") {
                unit = "ns"
                index = value.index(index, offsetBy: 2)
            } else if value[index...].hasPrefix("us") || value[index...].hasPrefix("µs") {
                unit = String(value[index...].prefix(2))
                index = value.index(index, offsetBy: 2)
            } else if value[index...].hasPrefix("ms") {
                unit = "ms"
                index = value.index(index, offsetBy: 2)
            } else if value[index...].hasPrefix("s") {
                unit = "s"
                index = value.index(after: index)
            } else if value[index...].hasPrefix("m") {
                unit = "m"
                index = value.index(after: index)
            } else if value[index...].hasPrefix("h") {
                unit = "h"
                index = value.index(after: index)
            } else {
                throw InvalidDurationError(value: value)
            }

            let multiplier: Double = switch unit {
            case "ns": 0.000000001
            case "us", "µs": 0.000001
            case "ms": 0.001
            case "s": 1
            case "m": 60
            case "h": 3600
            default: 0
            }
            total += amount * multiplier
            guard total.isFinite else { throw InvalidDurationError(value: value) }
            foundComponent = true
        }

        guard foundComponent, total >= 0, total <= Double(Int32.max) else {
            throw InvalidDurationError(value: value)
        }
        return total.rounded(.towardZero)
    }

    private struct InvalidDurationError: LocalizedError {
        let value: String

        var errorDescription: String? {
            "Invalid stop_grace_period duration: '\(value)'"
        }
    }
}
