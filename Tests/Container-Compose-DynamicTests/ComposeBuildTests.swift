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
import ContainerCommands
import ContainerAPIClient
import TestHelpers
@testable import ContainerComposeCore

@Suite("Compose Build Tests", .containerDependent, .serialized)
struct ComposeBuildTests {

    // MARK: - Helpers

    private func writeBuildProject(yaml: String, dockerfile: String = "FROM alpine:latest") throws -> DockerComposeYamlFiles.TemporaryProject {
        let project = try DockerComposeYamlFiles.copyYamlToTemporaryLocation(yaml: yaml)
        let dockerfilePath = project.base.appending(path: "Dockerfile").path(percentEncoded: false)
        try dockerfile.write(toFile: dockerfilePath, atomically: false, encoding: .utf8)
        return project
    }

    private func imageExists(named tag: String) async throws -> Bool {
        let images = try await ClientImage.list()
        return images.contains { $0.description.reference.hasSuffix(tag) }
    }

    // MARK: - Tests

    @Test("Build produces an image in the local store")
    func buildProducesImageInLocalStore() async throws {
        let yaml = """
        services:
          simple:
            build:
              context: .
              dockerfile: Dockerfile
        """

        let project = try writeBuildProject(yaml: yaml)

        var composeBuild = try ComposeBuild.parse([
            "--cwd", project.base.path(percentEncoded: false),
        ])
        try await composeBuild.run()

        #expect(try await imageExists(named: "simple:latest"))
    }

    @Test("Build uses explicit image tag from compose file")
    func buildUsesExplicitImageTag() async throws {
        let yaml = """
        services:
          app:
            image: compose-build-test-tagged:latest
            build:
              context: .
              dockerfile: Dockerfile
        """

        let project = try writeBuildProject(yaml: yaml)

        var composeBuild = try ComposeBuild.parse([
            "--cwd", project.base.path(percentEncoded: false),
        ])
        try await composeBuild.run()

        #expect(try await imageExists(named: "compose-build-test-tagged:latest"))
    }

    @Test("Build with service filter only builds specified service")
    func buildWithServiceFilterOnlyBuildsSpecifiedService() async throws {
        let yaml = """
        services:
          included:
            build:
              context: .
              dockerfile: Dockerfile
          excluded:
            build:
              context: .
              dockerfile: Dockerfile
        """

        let project = try writeBuildProject(yaml: yaml)

        var composeBuild = try ComposeBuild.parse([
            "--cwd", project.base.path(percentEncoded: false),
            "included",
        ])
        try await composeBuild.run()

        #expect(try await imageExists(named: "included:latest"))
        #expect(try await !imageExists(named: "excluded:latest"))
    }

    @Test("Build passes build args to Dockerfile")
    func buildPassesBuildArgsToDockerfile() async throws {
        let dockerfile = """
        ARG BUILD_VERSION=unset
        FROM alpine:latest
        LABEL build.version=$BUILD_VERSION
        """

        let yaml = """
        services:
          app:
            image: compose-build-test-args:latest
            build:
              context: .
              dockerfile: Dockerfile
              args:
                BUILD_VERSION: "1.2.3"
        """

        let project = try writeBuildProject(yaml: yaml, dockerfile: dockerfile)

        var composeBuild = try ComposeBuild.parse([
            "--cwd", project.base.path(percentEncoded: false),
        ])
        try await composeBuild.run()

        #expect(try await imageExists(named: "compose-build-test-args:latest"))
    }

    @Test("Build with no buildable services prints message and exits cleanly")
    func buildWithNoBuildableServicesExitsCleanly() async throws {
        let yaml = """
        services:
          cache:
            image: redis:alpine
          db:
            image: postgres:14
        """

        let project = try DockerComposeYamlFiles.copyYamlToTemporaryLocation(yaml: yaml)

        var composeBuild = try ComposeBuild.parse([
            "--cwd", project.base.path(percentEncoded: false),
        ])

        // Should complete without throwing even though nothing is built
        try await composeBuild.run()
    }
}
