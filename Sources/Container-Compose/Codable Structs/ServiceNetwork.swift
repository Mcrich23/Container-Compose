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

/// Service-specific network options for Compose object-form networks.
public struct ServiceNetwork: Codable, Hashable {
    /// Additional DNS aliases requested for this service on the network.
    public let aliases: [String]?

    /// Static IPv4 address requested by the Compose file.
    public let ipv4_address: String?

    /// Static IPv6 address requested by the Compose file.
    public let ipv6_address: String?

    public init(
        aliases: [String]? = nil,
        ipv4_address: String? = nil,
        ipv6_address: String? = nil
    ) {
        self.aliases = aliases
        self.ipv4_address = ipv4_address
        self.ipv6_address = ipv6_address
    }
}
