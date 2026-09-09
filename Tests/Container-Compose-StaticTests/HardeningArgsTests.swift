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

@Suite("Hardening Run Args")
struct HardeningArgsTests {

    private func service(_ yaml: String) throws -> Service {
        try YAMLDecoder().decode(Service.self, from: yaml)
    }

    @Test("cap_drop and cap_add parse")
    func capabilitiesParse() throws {
        let svc = try service("""
        image: alpine
        cap_drop:
          - ALL
        cap_add:
          - NET_BIND_SERVICE
        """)
        #expect(svc.cap_drop == ["ALL"])
        #expect(svc.cap_add == ["NET_BIND_SERVICE"])
    }

    /// Order is deliberately not asserted: `container` collects the two flags
    /// into separate arrays and computes the effective capability set, so the
    /// command-line order carries no meaning. What matters is that every
    /// declared capability reaches the right flag.
    @Test("every declared capability reaches its flag")
    func capabilitiesAreEmitted() throws {
        let svc = Service(
            image: "alpine",
            cap_add: ["NET_BIND_SERVICE", "CHOWN"],
            cap_drop: ["ALL"]
        )
        let args = ComposeUp.hardeningRunArgs(for: svc)
        #expect(args.count == 6)
        #expect(zip(args, args.dropFirst()).contains { $0 == "--cap-drop" && $1 == "ALL" })
        #expect(zip(args, args.dropFirst()).contains { $0 == "--cap-add" && $1 == "NET_BIND_SERVICE" })
        #expect(zip(args, args.dropFirst()).contains { $0 == "--cap-add" && $1 == "CHOWN" })
    }


    @Test("shm_size, init and ulimits parse")
    func scalarHardeningParse() throws {
        let svc = try service("""
        image: alpine
        shm_size: 256m
        init: true
        ulimits:
          nofile: 65535
        """)
        #expect(svc.shm_size == "256m")
        #expect(svc.runInit == true)
        #expect(svc.ulimits?["nofile"] == "65535")
    }

    @Test("shm_size, init and ulimits emit flags")
    func scalarHardeningArgs() throws {
        let svc = Service(image: "alpine", shm_size: "256m", runInit: true, ulimits: ["nofile": "65535"])
        let args = ComposeUp.hardeningRunArgs(for: svc)
        #expect(args.contains("--init"))
        #expect(args.firstIndex(of: "--shm-size").map { args[$0 + 1] } == "256m")
        #expect(args.firstIndex(of: "--ulimit").map { args[$0 + 1] } == "nofile=65535")
    }

    @Test("init false emits no flag")
    func initFalseEmitsNothing() throws {
        let svc = Service(image: "alpine", runInit: false)
        #expect(ComposeUp.hardeningRunArgs(for: svc).contains("--init") == false)
    }

    @Test("tmpfs list form parses")
    func tmpfsParses() throws {
        let svc = try service("""
        image: alpine
        tmpfs:
          - /run:noexec,nosuid
          - /tmp
        """)
        #expect(svc.tmpfs == ["/run:noexec,nosuid", "/tmp"])
    }

    @Test("tmpfs maps to --mount type=tmpfs, never --tmpfs")
    func tmpfsUsesMountFlag() throws {
        let svc = Service(image: "alpine", tmpfs: ["/tmp"])
        let args = ComposeUp.hardeningRunArgs(for: svc)
        #expect(args.contains("--tmpfs") == false)
        #expect(args.firstIndex(of: "--mount").map { args[$0 + 1] } == "type=tmpfs,target=/tmp")
    }

    @Test("tmpfs mode is carried through, unsupported options are not")
    func tmpfsCarriesModeOnly() throws {
        let svc = Service(image: "alpine", tmpfs: ["/run/postgresql:noexec,nosuid,uid=70,gid=70,mode=0755"])
        let args = ComposeUp.hardeningRunArgs(for: svc)
        let spec = try #require(args.firstIndex(of: "--mount").map { args[$0 + 1] })
        #expect(spec.contains("target=/run/postgresql"))
        #expect(spec.contains("mode=0755"))
        #expect(spec.contains("uid=") == false)
        #expect(spec.contains("noexec") == false)
    }

    @Test("dropped tmpfs options are reported, and uid/gid gets its own warning")
    func tmpfsDroppedOptionsAreReported() throws {
        let svc = Service(image: "alpine", tmpfs: ["/run/postgresql:noexec,nosuid,uid=70,gid=70,mode=0755"])
        let warnings = ComposeUp.unsupportedOptionWarnings(for: svc, serviceName: "patroni1")
        #expect(warnings.contains { $0.contains("noexec") && $0.contains("/run/postgresql") })
        #expect(warnings.contains { $0.contains("non-root") })
    }

    @Test("tmpfs with no options produces no warning")
    func tmpfsNoOptionsNoWarning() throws {
        let svc = Service(image: "alpine", tmpfs: ["/tmp"])
        #expect(ComposeUp.unsupportedOptionWarnings(for: svc, serviceName: "web").isEmpty)
    }

    @Test("network_mode parses")
    func networkModeParses() throws {
        let svc = try service("""
        image: alpine
        network_mode: none
        """)
        #expect(svc.network_mode == "none")
    }

    @Test("network_mode emits no run args")
    func networkModeEmitsNoArgs() throws {
        let svc = Service(image: "alpine", network_mode: "none")
        #expect(ComposeUp.hardeningRunArgs(for: svc).isEmpty)
    }

    @Test("network_mode is reported as unsupported")
    func networkModeIsReported() throws {
        let svc = Service(image: "alpine", network_mode: "none")
        let warnings = ComposeUp.unsupportedOptionWarnings(for: svc, serviceName: "etcd-init")
        #expect(warnings.contains { $0.contains("network_mode") && $0.contains("etcd-init") })
    }

    @Test("absent network_mode produces no warning")
    func absentNetworkModeNoWarning() throws {
        let svc = Service(image: "alpine")
        #expect(ComposeUp.unsupportedOptionWarnings(for: svc, serviceName: "web").isEmpty)
    }

    @Test("ulimits soft/hard long form maps to soft:hard")
    func ulimitsLongForm() throws {
        let svc = try service("""
        image: alpine
        ulimits:
          nproc: 65535
          nofile:
            soft: 20000
            hard: 40000
        """)
        #expect(svc.ulimits?["nproc"] == "65535")
        #expect(svc.ulimits?["nofile"] == "20000:40000")

        let args = ComposeUp.hardeningRunArgs(for: svc)
        #expect(zip(args, args.dropFirst()).contains { $0 == "--ulimit" && $1 == "nofile=20000:40000" })
        #expect(zip(args, args.dropFirst()).contains { $0 == "--ulimit" && $1 == "nproc=65535" })
    }

    @Test("an unreadable ulimits entry fails the file instead of nilling the map")
    func ulimitsMalformedThrows() throws {
        #expect(throws: (any Error).self) {
            try YAMLDecoder().decode(Service.self, from: """
            image: alpine
            ulimits:
              nofile:
                soft: 20000
            """)
        }
    }

    @Test("an unreadable tmpfs value fails the file instead of nilling it")
    func tmpfsMalformedThrows() throws {
        #expect(throws: (any Error).self) {
            try YAMLDecoder().decode(Service.self, from: """
            image: alpine
            tmpfs:
              run: true
            """)
        }
    }

    @Test("whitespace after a comma does not lose the option")
    func tmpfsOptionWhitespace() throws {
        let svc = Service(image: "alpine", tmpfs: ["/run:noexec, mode=0755"])
        let args = ComposeUp.hardeningRunArgs(for: svc)
        let spec = try #require(args.firstIndex(of: "--mount").map { args[$0 + 1] })
        #expect(spec.contains("mode=0755"))
        #expect(ComposeUp.unsupportedOptionWarnings(for: svc, serviceName: "web")
            .contains { $0.contains("noexec") })
    }

    @Test("variables are interpolated in the hardening keys")
    func hardeningKeysInterpolate() throws {
        let env = ["RUNTIME_DIR": "/run/app", "SHM": "512m", "NOFILE": "65535"]
        let svc = Service(
            image: "alpine",
            shm_size: "${SHM}",
            ulimits: ["nofile": "${NOFILE}"],
            tmpfs: ["${RUNTIME_DIR}:mode=0755"]
        )
        let args = ComposeUp.hardeningRunArgs(for: svc, environment: env)
        #expect(args.firstIndex(of: "--shm-size").map { args[$0 + 1] } == "512m")
        #expect(zip(args, args.dropFirst()).contains { $0 == "--ulimit" && $1 == "nofile=65535" })
        let spec = try #require(args.firstIndex(of: "--mount").map { args[$0 + 1] })
        #expect(spec.contains("target=/run/app"))
        #expect(spec.contains("${") == false)
    }

    @Test("no hardening keys yields no args")
    func emptyYieldsNothing() throws {
        let svc = Service(image: "alpine")
        #expect(ComposeUp.hardeningRunArgs(for: svc).isEmpty)
    }
}
