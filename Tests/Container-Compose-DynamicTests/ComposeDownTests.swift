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
import Foundation
import TestHelpers
import Testing

@testable import ContainerComposeCore

@Suite("Compose Down Tests", .containerDependent, .serialized)
struct ComposeDownTests {

    @Test("What goes up must come down - two containers")
    func testUpAndDownComplex() async throws {
        let yaml = DockerComposeYamlFiles.dockerComposeYaml1
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
            containers.count == 2,
            "Expected 2 containers for \(project.name), found \(containers.count)")

        #expect(containers.filter({ $0.status == .stopped}).count == 2, "Expected 2 stopped containers for \(project.name), found \(containers.filter({ $0.status == .stopped }).count)")
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
                command:
                  - sh
                  - -c
                  - |
                    trap 'touch /marker/term; sleep 10; touch /marker/graceful' TERM
                    touch /marker/ready
                    while true; do sleep 1; done
                volumes:
                  - \(markerDirectory.path):/marker
            """
        let project = try DockerComposeYamlFiles.copyYamlToTemporaryLocation(yaml: yaml)

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
            containers.count == 1,
            "Expected 1 container with the name \(containerName), found \(containers.count)")
        #expect(
            containers.filter({ $0.status == .stopped }).count == 1,
            "Expected container \(containerName) to be stopped, found status: \(containers.map(\.status))"
        )
    }

    enum Errors: Error {
        case containerNotFound
    }

}
