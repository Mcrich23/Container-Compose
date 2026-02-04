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

        var containers = try await ClientContainer.list()
            .filter({
                $0.configuration.id.contains(project.name)
            })

        #expect(
            containers.count == 2,
            "Expected 2 containers for \(project.name), found \(containers.count)")

        #expect(containers.filter({ $0.status == .running }).count == 2, "Expected 2 running containers for \(project.name), found \(containers.count)")

        var composeDown = try ComposeDown.parse(["--cwd", project.base.path(percentEncoded: false)])
        try await composeDown.run()

        containers = try await ClientContainer.list()
            .filter({
                $0.configuration.id.contains(project.name)
            })

        #expect(
            containers.count == 2,
            "Expected 2 containers for \(project.name), found \(containers.count)")

        #expect(containers.filter({ $0.status == .stopped}).count == 2, "Expected 2 stopped containers for \(project.name), found \(containers.count)")
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

        var containers = try await ClientContainer.list()
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

        var composeDown = try ComposeDown.parse(["--cwd", project.base.path(percentEncoded: false)])
        try await composeDown.run()

        containers = try await ClientContainer.list()
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
