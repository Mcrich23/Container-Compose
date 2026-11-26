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
import TerminalProgress
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

extension ComposePullTests {

    private func target(_ name: String, image: String?) -> ComposeProject.ServiceTarget {
        ComposeProject.ServiceTarget(
            serviceName: name,
            service: Service(image: image),
            candidateContainerNames: ["demo-\(name)"])
    }

    @Test("Services sharing an image pull it once, order preserved")
    func planDeduplicatesSharedImages() {
        let (items, buildOnly) = ComposePull.pullPlan(
            for: [target("a", image: "alpine:3"), target("b", image: "nginx:1"), target("c", image: "alpine:3")])
        #expect(items.map(\.image) == ["alpine:3", "nginx:1"])
        #expect(items[0].services == ["a", "c"])
        #expect(buildOnly.isEmpty)
    }

    @Test("Build-only services are reported separately, not pulled")
    func planSeparatesBuildOnly() {
        let (items, buildOnly) = ComposePull.pullPlan(
            for: [target("web", image: "nginx:1"), target("builder", image: nil)])
        #expect(items.map(\.image) == ["nginx:1"])
        #expect(buildOnly == ["builder"])
    }

    // MARK: - Progress rendering

    @Test("Progress line shows a bar, percent and sizes")
    func renderSizeProgress() {
        var line = PullProgressDisplay.Line(label: "web (nginx:1)")
        line.phase = "Fetching"
        line.size = 50
        line.totalSize = 100
        let out = PullProgressDisplay.render(line)
        #expect(out.hasPrefix("web (nginx:1)  Fetching [=========="))
        #expect(out.contains("50%"))
    }

    @Test("Progress events accumulate into the line")
    func applyEvents() {
        var line = PullProgressDisplay.Line(label: "x")
        for event: ProgressUpdateEvent in [.addTotalSize(200), .addSize(50), .addSize(50), .setTotalItems(4), .addItems(1)] {
            PullProgressDisplay.apply(event, to: &line)
        }
        #expect(line.size == 100)
        #expect(line.totalSize == 200)
        #expect(line.items == 1 && line.totalItems == 4)
    }

    @Test("Finished and failed lines replace the bar")
    func renderTerminalStates() {
        var line = PullProgressDisplay.Line(label: "x")
        line.done = true
        #expect(PullProgressDisplay.render(line) == "x  done")
        line.error = "boom"
        #expect(PullProgressDisplay.render(line) == "x  failed: boom")
    }
}
