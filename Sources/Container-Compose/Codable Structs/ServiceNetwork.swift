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

/// Service-level network options from Docker Compose map syntax.
public struct ServiceNetwork: Codable, Hashable {
    /// Network-scoped service aliases.
    public let aliases: [String]?

    /// Driver options applied to this network attachment.
    public let driver_opts: [String: String]?

    /// Gateway priority for this network attachment.
    public let gw_priority: Int?

    /// Requested interface name inside the container.
    public let interface_name: String?

    /// Requested static IPv4 address.
    public let ipv4_address: String?

    /// Requested static IPv6 address.
    public let ipv6_address: String?

    /// Link-local IP addresses for this network attachment.
    public let link_local_ips: [String]?

    /// Requested MAC address for this network attachment.
    public let mac_address: String?

    /// Network attachment priority.
    public let priority: Int?

    public init(
        aliases: [String]? = nil,
        driver_opts: [String: String]? = nil,
        gw_priority: Int? = nil,
        interface_name: String? = nil,
        ipv4_address: String? = nil,
        ipv6_address: String? = nil,
        link_local_ips: [String]? = nil,
        mac_address: String? = nil,
        priority: Int? = nil
    ) {
        self.aliases = aliases
        self.driver_opts = driver_opts
        self.gw_priority = gw_priority
        self.interface_name = interface_name
        self.ipv4_address = ipv4_address
        self.ipv6_address = ipv6_address
        self.link_local_ips = link_local_ips
        self.mac_address = mac_address
        self.priority = priority
    }
}
