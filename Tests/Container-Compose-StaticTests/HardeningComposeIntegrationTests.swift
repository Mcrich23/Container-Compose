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

/// The per-key tests in `HardeningArgsTests` build a `Service` directly. These
/// exercise the same keys through a whole compose document that uses a YAML
/// anchor and merge keys, which is how hardening settings are usually shared
/// across services in real files. A parser that silently failed to resolve
/// `<<:` would pass every per-key test and fail here.
@Suite("Hardening Keys Through A Compose Document")
struct HardeningComposeIntegrationTests {

    private static let yaml = """
    x-common: &common
      cap_drop:
        - ALL
      init: true
      read_only: true

    services:
      web:
        <<: *common
        image: nginx:alpine
        cap_add:
          - NET_BIND_SERVICE
        tmpfs:
          - /run:noexec,nosuid,uid=70,gid=70,mode=0755
      db:
        <<: *common
        image: postgres:16
        shm_size: 256m
        ulimits:
          nofile: 65535
      fixer:
        <<: *common
        image: alpine:3
        network_mode: none
    """

    private func compose() throws -> DockerCompose {
        try YAMLDecoder().decode(DockerCompose.self, from: Self.yaml)
    }

    private func service(_ name: String) throws -> Service {
        let svc = try compose().services[name]
        return try #require(svc ?? nil)
    }

    @Test("merge keys carry hardening settings to every service")
    func mergeKeysResolve() throws {
        let compose = try compose()
        #expect(compose.services.count == 3)
        for name in ["web", "db", "fixer"] {
            let svc = try service(name)
            #expect(svc.cap_drop == ["ALL"], "\(name) did not inherit cap_drop")
            #expect(svc.runInit == true, "\(name) did not inherit init")
            #expect(svc.read_only == true, "\(name) did not inherit read_only")
        }
    }

    @Test("inherited and per-service capabilities both reach the command line")
    func capabilitiesCombine() throws {
        let args = ComposeUp.hardeningRunArgs(for: try service("web"))
        #expect(zip(args, args.dropFirst()).contains { $0 == "--cap-drop" && $1 == "ALL" })
        #expect(zip(args, args.dropFirst()).contains { $0 == "--cap-add" && $1 == "NET_BIND_SERVICE" })
    }

    @Test("tmpfs keeps mode, drops what container run cannot express, and says so")
    func tmpfsThroughDocument() throws {
        let svc = try service("web")
        let args = ComposeUp.hardeningRunArgs(for: svc)
        let spec = try #require(args.firstIndex(of: "--mount").map { args[$0 + 1] })
        #expect(spec.contains("target=/run"))
        #expect(spec.contains("mode=0755"))
        #expect(spec.contains("uid=") == false)

        let warnings = ComposeUp.unsupportedOptionWarnings(for: svc, serviceName: "web")
        #expect(warnings.contains { $0.contains("noexec") })
        #expect(warnings.contains { $0.contains("non-root") })
    }

    @Test("scalar hardening keys survive the document round trip")
    func scalarsThroughDocument() throws {
        let args = ComposeUp.hardeningRunArgs(for: try service("db"))
        #expect(args.firstIndex(of: "--shm-size").map { args[$0 + 1] } == "256m")
        #expect(args.firstIndex(of: "--ulimit").map { args[$0 + 1] } == "nofile=65535")
        #expect(args.contains("--init"))
    }

    @Test("network_mode produces a warning and no run args")
    func networkModeThroughDocument() throws {
        let svc = try service("fixer")
        #expect(ComposeUp.hardeningRunArgs(for: svc).contains("--network") == false)
        #expect(ComposeUp.unsupportedOptionWarnings(for: svc, serviceName: "fixer")
            .contains { $0.contains("network_mode") })
    }
}
