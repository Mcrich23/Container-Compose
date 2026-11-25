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

import ContainerAPIClient
import ContainerCommands
import ContainerResource
import Foundation
import TestHelpers
import Testing

@testable import ContainerComposeCore

@Suite("Compose Down Tests", .containerDependent, .serialized)
struct ComposeDownTests {

    @Test("Cleanup requires ownership and preserves external resources")
    func resourceOwnership() async throws {
        let project = try DockerComposeYamlFiles.copyYamlToTemporaryLocation(yaml: "services: {}")
        defer { try? FileManager.default.removeItem(at: project.base) }
        let owned = "\(project.name)_owned".lowercased()
        let legacy = "\(project.name)_legacy"
        let external = "\(project.name)_external"
        try "services: {}\nvolumes:\n  external:\n    name: \(external)\n    external: true\n".write(to: project.url, atomically: true, encoding: .utf8)
        let networkClient = NetworkClient()
        _ = try await networkClient.create(configuration: NetworkConfiguration(
            name: owned, mode: .nat,
            labels: ResourceLabels(ComposeResources.labels(project: project.name)),
            plugin: "container-network-vmnet"))
        _ = try await ClientVolume.create(name: owned, labels: ComposeResources.labels(project: project.name))
        _ = try await ClientVolume.create(name: legacy)
        _ = try await ClientVolume.create(name: external, labels: ComposeResources.labels(project: project.name))
        do {
            let down = try ComposeDown.parse(["--cwd", project.base.path, "--volumes"])
            try await down.run()
            #expect(try await networkClient.list().allSatisfy { $0.id != owned })
            let volumes = try await ClientVolume.list()
            #expect(!volumes.contains { $0.name == owned })
            #expect(volumes.contains { $0.name == legacy })
            #expect(volumes.contains { $0.name == external })
        } catch {
            try? await networkClient.delete(id: owned)
            try? await ClientVolume.delete(name: owned)
            try? await ClientVolume.delete(name: legacy)
            try? await ClientVolume.delete(name: external)
            throw error
        }
        try await ClientVolume.delete(name: legacy)
        try await ClientVolume.delete(name: external)
    }

    @Test("Reverse teardown preserves resources attached to an inactive service")
    func orderAndSurvivingResources() async throws {
        let marker = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: marker) }
        let yaml = """
            services:
              base:
                image: alpine:latest
                command: [sh, -c, "trap 'echo base >> /marker/order; exit 0' TERM; touch /marker/base; while true; do sleep 1; done"]
                volumes: ["\(marker.path):/marker"]
              dependent:
                image: alpine:latest
                depends_on: [base]
                command: [sh, -c, "trap 'echo dependent >> /marker/order; exit 0' TERM; touch /marker/dependent; while true; do sleep 1; done"]
                volumes: ["\(marker.path):/marker", "/anonymous"]
              survivor:
                image: alpine:latest
                profiles: [keep]
                command: [sleep, '300']
                volumes: ["data:/data"]
            volumes:
              data: {}
            """
        let project = try DockerComposeYamlFiles.copyYamlToTemporaryLocation(yaml: yaml)
        do {
            var up = try ComposeUp.parse(["--cwd", project.base.path, "--profile", "keep", "-d"])
            try await up.run()
            let deadline = Date().addingTimeInterval(30)
            while (!FileManager.default.fileExists(atPath: marker.appending(path: "base").path)
                   || !FileManager.default.fileExists(atPath: marker.appending(path: "dependent").path)), Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            let down = try ComposeDown.parse(["--cwd", project.base.path, "--volumes", "--remove-orphans"])
            try await down.run()
            let order = try String(contentsOf: marker.appending(path: "order"), encoding: .utf8)
            #expect(order.split(separator: "\n") == ["dependent", "base"])
            let survivors = try await ContainerClient().list().filter {
                $0.configuration.labels["com.docker.compose.project"] == project.name
            }
            #expect(survivors.count == 1)
            #expect(survivors.first?.configuration.labels["com.docker.compose.service"] == "survivor")
            let remainingVolumes = try await ClientVolume.list().filter {
                ComposeResources.owns($0.labels, project: project.name)
            }
            #expect(remainingVolumes.map(\.name) == ["\(project.name)_data"])
            let network = ComposeResources.networkName("default", config: nil, project: project.name)
            #expect(try await NetworkClient().list().contains { $0.id == network })
        } catch {
            let cleanup = try ComposeDown.parse(["--cwd", project.base.path, "--profile", "keep", "--volumes"])
            try? await cleanup.run()
            try? FileManager.default.removeItem(at: project.base)
            throw error
        }
        let cleanup = try ComposeDown.parse(["--cwd", project.base.path, "--profile", "keep", "--volumes"])
        try await cleanup.run()
        try FileManager.default.removeItem(at: project.base)
    }

    @Test("What goes up must come down - two containers")
    func testUpAndDownComplex() async throws {
        let yaml = DockerComposeYamlFiles.dockerComposeYaml1.replacingOccurrences(of: "    ports:\n      - \"8080:80\"\n", with: "")
        let project = try DockerComposeYamlFiles.copyYamlToTemporaryLocation(yaml: yaml)

        var composeUp = try ComposeUp.parse([
            "-d", "--cwd", project.base.path(percentEncoded: false),
        ])
        try await composeUp.run()

        var containers = try await ContainerClient().list()
            .filter({
                $0.configuration.id.contains(project.name)
            })

        #expect(
            containers.count == 2,
            "Expected 2 containers for \(project.name), found \(containers.count)")

        #expect(containers.filter({ $0.status == .running }).count == 2, "Expected 2 running containers for \(project.name), found \(containers.filter({ $0.status == .running }).count)")

        let composeDown = try ComposeDown.parse(["--cwd", project.base.path(percentEncoded: false)])
        try await composeDown.run()

        containers = try await ContainerClient().list()
            .filter({
                $0.configuration.id.contains(project.name)
            })

        #expect(
            containers.isEmpty,
            "Expected removed containers for \(project.name), found \(containers.count)")
    }

    @Test("stop_grace_period controls the graceful stop deadline")
    func testStopGracePeriod() async throws {
        let markerDirectory = FileManager.default.temporaryDirectory
            .appending(path: makeContainerName())
        try FileManager.default.createDirectory(at: markerDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: markerDirectory) }

        let yaml = """
            services:
              app:
                image: alpine:latest
                stop_grace_period: 1s
                stop_signal: SIGUSR1
                command:
                  - sh
                  - -c
                  - |
                    trap 'touch /marker/term; sleep 10; touch /marker/graceful' USR1
                    touch /marker/ready
                    while true; do sleep 1; done
                volumes:
                  - \(markerDirectory.path):/marker
            """
        let project = try DockerComposeYamlFiles.copyYamlToTemporaryLocation(yaml: yaml)
        // Failure-safe cleanup: `defer` cannot `await`, so force-delete via
        // sync `Process` (covers running containers too). Uses the same
        // candidate names `down` stops so a throw before/after `down`
        // never leaks the infinite-loop container. Best-effort, never throws.
        defer {
            let ids = ComposeProject.candidateContainerNames(
                serviceName: "app",
                service: Service(image: "alpine:latest"),
                projectName: project.name
            )
            forceDeleteContainers(ids: ids)
            try? FileManager.default.removeItem(at: project.base)
        }

        var composeUp = try ComposeUp.parse([
            "-d", "--cwd", project.base.path(percentEncoded: false),
        ])
        try await composeUp.run()

        let readyMarker = markerDirectory.appending(path: "ready")
        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: readyMarker.path), Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(FileManager.default.fileExists(atPath: readyMarker.path))

        let stopStarted = Date()
        let composeDown = try ComposeDown.parse(["--cwd", project.base.path(percentEncoded: false)])
        try await composeDown.run()
        let stopElapsed = Date().timeIntervalSince(stopStarted)

        #expect(stopElapsed < 4, "stop_grace_period was not applied; stop took \(stopElapsed)s")
        #expect(FileManager.default.fileExists(atPath: markerDirectory.appending(path: "term").path))
        #expect(!FileManager.default.fileExists(atPath: markerDirectory.appending(path: "graceful").path))
    }

    @Test("What goes up must come down - container_name")
    func testUpAndDownContainerName() async throws {
        // Create a new temporary UUID to use as a container name, otherwise we might conflict with
        // existing containers on the system
        let containerName = UUID().uuidString

        let yaml = DockerComposeYamlFiles.dockerComposeYaml9(containerName: containerName)
        let project = try DockerComposeYamlFiles.copyYamlToTemporaryLocation(yaml: yaml)

        var composeUp = try ComposeUp.parse([
            "-d", "--cwd", project.base.path(percentEncoded: false),
        ])
        try await composeUp.run()

        var containers = try await ContainerClient().list()
            .filter({
                $0.configuration.id.contains(containerName)
            })

        #expect(
            containers.count == 1,
            "Expected 1 container with the name \(containerName), found \(containers.count)")
        #expect(
            containers.filter({ $0.status == .running}).count == 1,
            "Expected container \(containerName) to be running, found status: \(containers.map(\.status))"
        )

        let composeDown = try ComposeDown.parse(["--cwd", project.base.path(percentEncoded: false)])
        try await composeDown.run()

        containers = try await ContainerClient().list()
            .filter({
                $0.configuration.id.contains(containerName)
            })

        #expect(
            containers.isEmpty,
            "Expected container \(containerName) to be removed")
    }

    /// Synchronously force-delete containers by ID. Sync so it can run in
    /// `defer` (which cannot `await`); mirrors `ComposeUpDnsTests` cleanup.
    private func forceDeleteContainers(ids: [String]) {
        for id in ids {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["container", "delete", "-f", id]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
    }

    enum Errors: Error {
        case containerNotFound
    }

}
