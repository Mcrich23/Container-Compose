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

@Suite("Compose ps Tests")
struct ComposePsTests {

    // MARK: - Container selection

    /// Minimal stand-in for a daemon container snapshot.
    private struct FakeContainer: Equatable {
        let id: String
        let labels: [String: String]
        var running = true
    }

    /// A resolved two-service project (`web` depends on nothing, order web, db)
    /// named `demo`, with the standard candidate names.
    private func demoProject() throws -> ComposeProject {
        let compose = try YAMLDecoder().decode(
            DockerCompose.self,
            from: """
            name: demo
            services:
              web-x:
                image: nginx
              db:
                image: postgres
            """)
        let targets = [
            ComposeProject.ServiceTarget(
                serviceName: "web-x", service: Service(image: "nginx"),
                candidateContainerNames: ["demo-web-x", "web-x.demo"]),
            ComposeProject.ServiceTarget(
                serviceName: "db", service: Service(image: "postgres"),
                candidateContainerNames: ["demo-db", "db.demo"]),
        ]
        return ComposeProject(compose: compose, projectName: "demo", services: targets)
    }

    private func selectIDs(_ containers: [FakeContainer], in project: ComposeProject, all: Bool = true) -> [String] {
        ComposePs.select(
            containers, for: project, all: all,
            id: \.id, labels: \.labels, isRunning: \.running
        ).map(\.id)
    }

    @Test("A container labeled for another project is excluded even when its name collides with a candidate")
    func foreignProjectLabelBeatsNameCollision() throws {
        // `demo-web-x` is our candidate name for service `web-x` — but this
        // container's labels say it belongs to project `demo-web`, service `x`.
        let foreign = FakeContainer(
            id: "demo-web-x",
            labels: ["com.docker.compose.project": "demo-web", "com.docker.compose.service": "x"])
        #expect(try selectIDs([foreign], in: demoProject()) == [])
    }

    @Test("Labeled containers filter by project and service labels, not by name")
    func labelFiltering() throws {
        let ours = FakeContainer(
            id: "some-unrelated-name",
            labels: ["com.docker.compose.project": "demo", "com.docker.compose.service": "web-x"])
        let wrongService = FakeContainer(
            id: "demo-db",
            labels: ["com.docker.compose.project": "demo", "com.docker.compose.service": "cache"])
        let otherProject = FakeContainer(
            id: "elsewhere",
            labels: ["com.docker.compose.project": "other", "com.docker.compose.service": "web-x"])
        #expect(try selectIDs([ours, wrongService, otherProject], in: demoProject()) == ["some-unrelated-name"])
    }

    @Test("Unlabeled containers fall back to candidate-name matching")
    func unlabeledNameFallback() throws {
        let legacyDashed = FakeContainer(id: "demo-web-x", labels: [:])
        let legacyDotted = FakeContainer(id: "db.demo", labels: [:])
        let unrelated = FakeContainer(id: "somethingelse", labels: [:])
        // Ordered by the project's service order (web-x before db).
        #expect(try selectIDs([legacyDotted, unrelated, legacyDashed], in: demoProject()) == ["demo-web-x", "db.demo"])
    }

    @Test("Stopped containers are hidden by default and shown with --all")
    func stoppedContainerVisibility() throws {
        let running = FakeContainer(
            id: "a", labels: ["com.docker.compose.project": "demo", "com.docker.compose.service": "web-x"])
        let stopped = FakeContainer(
            id: "b", labels: ["com.docker.compose.project": "demo", "com.docker.compose.service": "db"],
            running: false)
        #expect(try selectIDs([running, stopped], in: demoProject(), all: false) == ["a"])
        #expect(try selectIDs([running, stopped], in: demoProject(), all: true) == ["a", "b"])
    }

    // MARK: - TableFormatter

    @Test("Table columns align and the trailing column is unpadded")
    func tableFormatting() {
        let out = TableFormatter.render(
            header: ["NAME", "STATUS"],
            rows: [["web", "running"], ["database", "stopped"]])
        let lines = out.split(separator: "\n").map(String.init)
        #expect(lines == [
            "NAME       STATUS",
            "web        running",
            "database   stopped",
        ])
    }

    // MARK: - CLI parsing

    @Test("ps accepts -a and service arguments alongside the project option group")
    func psParsesArguments() throws {
        let cmd = try ComposePs.parse(["-a", "web"])
        #expect(cmd.all)
        #expect(cmd.services == ["web"])
    }
}
