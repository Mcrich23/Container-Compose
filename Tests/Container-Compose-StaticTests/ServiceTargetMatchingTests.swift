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
@testable import ContainerComposeCore

@Suite("Shared container matching Tests")
struct ServiceTargetMatchingTests {

    private let target = ComposeProject.ServiceTarget(
        serviceName: "web-x", service: Service(image: "nginx"),
        candidateContainerNames: ["demo-web-x", "web-x.demo"])

    // MARK: - ownsContainer

    @Test("A container labeled for another project is never ours")
    func foreignProjectLabel() {
        #expect(!ComposeProject.ownsContainer(
            labels: ["com.docker.compose.project": "demo-web"], projectName: "demo"))
    }

    @Test("Matching-label and unlabeled containers are ours")
    func ownedContainers() {
        #expect(ComposeProject.ownsContainer(
            labels: ["com.docker.compose.project": "demo"], projectName: "demo"))
        #expect(ComposeProject.ownsContainer(labels: [:], projectName: "demo"))
    }

    // MARK: - ServiceTarget.matches

    @Test("Foreign-project label beats a candidate-name collision")
    func foreignLabelBeatsNameCollision() {
        #expect(!target.matches(
            containerID: "demo-web-x",
            labels: ["com.docker.compose.project": "demo-web", "com.docker.compose.service": "x"],
            projectName: "demo"))
    }

    @Test("Labeled containers match by service label, regardless of name")
    func labeledMatchIgnoresName() {
        let labels = ["com.docker.compose.project": "demo", "com.docker.compose.service": "web-x"]
        #expect(target.matches(containerID: "whatever-name", labels: labels, projectName: "demo"))
        let wrongService = ["com.docker.compose.project": "demo", "com.docker.compose.service": "db"]
        #expect(!target.matches(containerID: "demo-web-x", labels: wrongService, projectName: "demo"))
    }

    @Test("Unlabeled containers fall back to candidate names")
    func unlabeledNameFallback() {
        #expect(target.matches(containerID: "web-x.demo", labels: [:], projectName: "demo"))
        #expect(!target.matches(containerID: "unrelated", labels: [:], projectName: "demo"))
    }
}
