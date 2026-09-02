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

import Testing
import Foundation
@testable import Yams
@testable import ContainerComposeCore

@Suite("Top-level Network Name Interpolation")
struct NetworkNameInterpolationTests {

    private func network(_ yaml: String) throws -> Network {
        try YAMLDecoder().decode(Network.self, from: yaml)
    }

    @Test("an explicit name is interpolated")
    func explicitNameInterpolates() throws {
        let net = try network("name: ${INGRESS_NET}")
        let resolved = ComposeUp.resolvedNetworkName(
            key: "reverse-proxy",
            config: net,
            environment: ["INGRESS_NET": "prod-ingress"]
        )
        #expect(resolved == "prod-ingress")
    }

    @Test("a default value is used when the variable is unset")
    func defaultValueIsHonoured() throws {
        let net = try network("name: ${INGRESS_NET:-local-ingress}")
        let resolved = ComposeUp.resolvedNetworkName(
            key: "reverse-proxy",
            config: net,
            environment: [:]
        )
        #expect(resolved == "local-ingress")
    }

    @Test("the environment wins over the default")
    func environmentBeatsDefault() throws {
        let net = try network("name: ${INGRESS_NET:-local-ingress}")
        let resolved = ComposeUp.resolvedNetworkName(
            key: "reverse-proxy",
            config: net,
            environment: ["INGRESS_NET": "dev-cluster-ingress"]
        )
        #expect(resolved == "dev-cluster-ingress")
    }

    @Test("without an explicit name the key is used, and is itself interpolated")
    func keyFallbackAlsoInterpolates() throws {
        #expect(
            ComposeUp.resolvedNetworkName(key: "dcf-db", config: nil, environment: [:])
                == "dcf-db"
        )
        #expect(
            ComposeUp.resolvedNetworkName(
                key: "${NET_PREFIX}-db",
                config: nil,
                environment: ["NET_PREFIX": "dcf"]
            ) == "dcf-db"
        )
    }

    @Test("a plain name is passed through unchanged")
    func plainNameUnchanged() throws {
        let net = try network("name: dcf-vpc")
        #expect(
            ComposeUp.resolvedNetworkName(key: "vpc", config: net, environment: ["X": "y"])
                == "dcf-vpc"
        )
    }
}
