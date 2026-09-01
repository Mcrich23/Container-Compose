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

    @Test("cap_drop is emitted before cap_add")
    func capabilityOrder() throws {
        let svc = Service(image: "alpine", cap_add: ["NET_BIND_SERVICE"], cap_drop: ["ALL"])
        let args = ComposeUp.hardeningRunArgs(for: svc)
        #expect(args == ["--cap-drop", "ALL", "--cap-add", "NET_BIND_SERVICE"])
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
    @Test("no hardening keys yields no args")
    func emptyYieldsNothing() throws {
        let svc = Service(image: "alpine")
        #expect(ComposeUp.hardeningRunArgs(for: svc).isEmpty)
    }
}
