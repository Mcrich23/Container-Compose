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
import Yams
@testable import ContainerComposeCore

@Suite("Compose pull Tests")
struct ComposePullTests {

    /// A resolved project where the shared selection has already expanded
    /// `web`'s dependency on `db` (topological order: db before web).
    private func expandedProject() throws -> ComposeProject {
        let compose = try YAMLDecoder().decode(
            DockerCompose.self,
            from: """
            name: demo
            services:
              web:
                image: nginx
                depends_on: [db]
              db:
                image: postgres
            """)
        let targets = [
            ComposeProject.ServiceTarget(
                serviceName: "db", service: Service(image: "postgres"),
                candidateContainerNames: ["demo-db", "db.demo"]),
            ComposeProject.ServiceTarget(
                serviceName: "web", service: Service(image: "nginx"),
                candidateContainerNames: ["demo-web", "web.demo"]),
        ]
        return ComposeProject(compose: compose, projectName: "demo", services: targets)
    }

    // MARK: - Service selection

    @Test("Explicitly requested services do not pull their dependencies")
    func requestedServicesExcludeDependencies() throws {
        let targets = ComposePull.pullTargets(in: try expandedProject(), requested: ["web"], includeDeps: false)
        #expect(targets.map(\.serviceName) == ["web"])
    }

    @Test("--include-deps pulls the expanded dependency set")
    func includeDepsPullsDependencies() throws {
        let targets = ComposePull.pullTargets(in: try expandedProject(), requested: ["web"], includeDeps: true)
        #expect(targets.map(\.serviceName) == ["db", "web"])
    }

    @Test("No requested services pulls the whole selection")
    func defaultPullsEverything() throws {
        let targets = ComposePull.pullTargets(in: try expandedProject(), requested: [], includeDeps: false)
        #expect(targets.map(\.serviceName) == ["db", "web"])
    }

    // MARK: - Image reference resolution

    @Test("Variables in image references resolve from the environment")
    func imageVariableResolution() {
        let service = Service(image: "${REGISTRY}/app:${TAG}")
        let image = ComposePull.resolvedImage(for: service, environment: ["REGISTRY": "ghcr.io/acme", "TAG": "1.2"])
        #expect(image == "ghcr.io/acme/app:1.2")
    }

    @Test("Variable defaults apply when the variable is unset")
    func imageVariableDefault() {
        let service = Service(image: "nginx:${CC_PULL_TEST_UNSET:-latest}")
        #expect(ComposePull.resolvedImage(for: service, environment: [:]) == "nginx:latest")
    }

    @Test("Plain references pass through and build-only services resolve to nil")
    func imagePassthroughAndBuildOnly() throws {
        #expect(ComposePull.resolvedImage(for: Service(image: "nginx:1.27"), environment: [:]) == "nginx:1.27")
        let buildOnly = try YAMLDecoder().decode(Service.self, from: "build: .\n")
        #expect(ComposePull.resolvedImage(for: buildOnly, environment: [:]) == nil)
    }

    // MARK: - CLI parsing

    @Test("pull accepts service arguments alongside the project option group")
    func pullParsesArguments() throws {
        let cmd = try ComposePull.parse(["web", "db"])
        #expect(cmd.services == ["web", "db"])
        #expect(!cmd.includeDeps)
    }

    @Test("pull accepts --include-deps")
    func pullParsesIncludeDeps() throws {
        let cmd = try ComposePull.parse(["--include-deps", "web"])
        #expect(cmd.includeDeps)
    }

    @Test("pull accepts the shared -f/--cwd project options")
    func pullParsesProjectOptions() throws {
        let cmd = try ComposePull.parse(["-f", "my-compose.yaml", "--cwd", "/tmp"])
        #expect(cmd.project.composeFileOptions.composeFilename == "my-compose.yaml")
        #expect(cmd.project.cwd == "/tmp")
    }
}
