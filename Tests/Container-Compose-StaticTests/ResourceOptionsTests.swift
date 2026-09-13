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

@Suite("Resource options")
struct ResourceOptionsTests {
    private func service(from yaml: String) throws -> Service {
        let compose = try YAMLDecoder().decode(DockerCompose.self, from: yaml)
        return try #require(compose.services["app"] ?? nil)
    }

    @Test("Parse service-level resource shorthands")
    func parseServiceLevelShorthands() throws {
        let service = try service(from: """
        services:
          app:
            image: alpine
            cpus: 1.5
            mem_limit: 512m
            mem_reservation: 256m
            shm_size: 1g
            tmpfs: /run
            ulimits:
              nofile: 65535
              nproc:
                soft: 1024
                hard: 2048
            devices:
              - /dev/kvm:/dev/kvm
        """)

        #expect(service.cpus == "1.5")
        #expect(service.mem_limit == "512m")
        #expect(service.mem_reservation == "256m")
        #expect(service.shm_size == "1g")
        #expect(service.tmpfs == ["/run"])
        #expect(service.ulimits?["nofile"]?.soft == "65535")
        #expect(service.ulimits?["nofile"]?.hard == "65535")
        #expect(service.ulimits?["nproc"]?.soft == "1024")
        #expect(service.ulimits?["nproc"]?.hard == "2048")
        #expect(service.devices == ["/dev/kvm:/dev/kvm"])
    }

    @Test("Parse tmpfs list form and numeric cpus")
    func parseTmpfsListAndNumericCpus() throws {
        let service = try service(from: """
        services:
          app:
            image: alpine
            cpus: 2
            tmpfs:
              - /run
              - /tmp
        """)

        #expect(service.cpus == "2")
        #expect(service.tmpfs == ["/run", "/tmp"])
    }

    @Test("Resource args map limits, shm, tmpfs, and ulimits")
    func resourceArgsMap() {
        let service = Service(
            image: "alpine",
            mem_limit: "1g",
            cpus: "2",
            shm_size: "512m",
            tmpfs: ["/run"],
            ulimits: ["nofile": Ulimit(soft: "1024", hard: "2048")]
        )

        let result = ResourceArguments.runArgs(for: service, serviceName: "app", environmentVariables: [:])
        #expect(result.args == [
            "--cpus", "2",
            "--memory", "1g",
            "--shm-size", "512m",
            "--tmpfs", "/run",
            "--ulimit", "nofile=1024:2048",
        ])
    }

    @Test("Soft-only ulimit emits a single value")
    func softOnlyUlimit() {
        let service = Service(image: "alpine", ulimits: ["nproc": Ulimit(soft: "512")])
        let result = ResourceArguments.runArgs(for: service, serviceName: "app", environmentVariables: [:])
        #expect(result.args == ["--ulimit", "nproc=512"])
    }

    @Test("mem_limit is clamped to Apple Container's 200 MiB minimum")
    func memoryClamped() {
        let service = Service(image: "alpine", mem_limit: "128m")
        let result = ResourceArguments.runArgs(for: service, serviceName: "app", environmentVariables: [:])
        #expect(result.args == ["--memory", "200m"])
        #expect(result.notes.contains { $0.contains("clamping") })
    }

    @Test("Fractional cpus round up for Apple Container")
    func fractionalCpusRoundUp() {
        let service = Service(image: "alpine", cpus: "1.5")
        let result = ResourceArguments.runArgs(for: service, serviceName: "app", environmentVariables: [:])
        #expect(result.args == ["--cpus", "2"])
        #expect(result.notes.contains { $0.contains("rounding up") })
    }

    @Test("Deploy limits win over service-level cpus shorthand")
    func cpusPrecedence() throws {
        let service = try service(from: """
        services:
          app:
            image: alpine
            cpus: "8"
            deploy:
              resources:
                limits:
                  cpus: "2"
        """)

        let result = ResourceArguments.runArgs(for: service, serviceName: "app", environmentVariables: [:])
        #expect(result.args == ["--cpus", "2"])
        #expect(result.notes.contains { $0.contains("using the official deploy limit") })
    }

    @Test("Deploy limits apply on their own")
    func deployLimitsOnly() throws {
        let service = try service(from: """
        services:
          app:
            image: alpine
            deploy:
              resources:
                limits:
                  cpus: "3"
                  memory: 1g
        """)

        let result = ResourceArguments.runArgs(for: service, serviceName: "app", environmentVariables: [:])
        #expect(result.args == ["--cpus", "3", "--memory", "1g"])
    }

    @Test("Deploy memory limit wins over mem_limit shorthand")
    func memoryPrecedence() throws {
        let service = try service(from: """
        services:
          app:
            image: alpine
            mem_limit: 512m
            deploy:
              resources:
                limits:
                  memory: 1g
        """)

        let result = ResourceArguments.runArgs(for: service, serviceName: "app", environmentVariables: [:])
        #expect(result.args == ["--memory", "1g"])
        #expect(result.notes.contains { $0.contains("using the official deploy limit") })
    }

    @Test("Memory reservation becomes the hard limit when no limit is set")
    func reservationAsHardLimit() throws {
        let service = try service(from: """
        services:
          app:
            image: alpine
            mem_reservation: 256m
        """)

        let result = ResourceArguments.runArgs(for: service, serviceName: "app", environmentVariables: [:])
        #expect(result.args == ["--memory", "256m"])
        #expect(result.notes.contains { $0.contains("soft memory limit") })
    }

    @Test("Reservation is ignored when a hard limit exists")
    func reservationIgnoredWithHardLimit() throws {
        let service = try service(from: """
        services:
          app:
            image: alpine
            mem_limit: 1g
            mem_reservation: 256m
        """)

        let result = ResourceArguments.runArgs(for: service, serviceName: "app", environmentVariables: [:])
        #expect(result.args == ["--memory", "1g"])
        #expect(result.notes.contains { $0.contains("ignoring the reservation") })
    }

    @Test("Unsupported reservations and devices produce notes")
    func unsupportedResourcesProduceNotes() throws {
        let service = try service(from: """
        services:
          app:
            image: alpine
            devices:
              - /dev/kvm:/dev/kvm
            deploy:
              mode: replicated
              replicas: 3
              resources:
                reservations:
                  cpus: "0.5"
                  devices:
                    - capabilities: [gpu]
        """)

        let result = ResourceArguments.runArgs(for: service, serviceName: "app", environmentVariables: [:])
        #expect(result.notes.contains { $0.contains("orchestration fields") })
        #expect(result.notes.contains { $0.contains("reservations.cpus") })
        #expect(result.notes.contains { $0.contains("device/GPU reservations") })
        #expect(result.notes.contains { $0.contains("device mappings") })
    }

    @Test("Environment variables resolve in resource values")
    func environmentVariablesResolve() {
        let service = Service(image: "alpine", cpus: "${CPUS}", shm_size: "${SHM}")
        let result = ResourceArguments.runArgs(
            for: service,
            serviceName: "app",
            environmentVariables: ["CPUS": "4", "SHM": "256m"]
        )
        #expect(result.args == ["--cpus", "4", "--shm-size", "256m"])
    }
}
