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

    /// Requested static IPv4 address.
    public let ipv4_address: String?

    public init(aliases: [String]? = nil, ipv4_address: String? = nil) {
        self.aliases = aliases
        self.ipv4_address = ipv4_address
    }
}
