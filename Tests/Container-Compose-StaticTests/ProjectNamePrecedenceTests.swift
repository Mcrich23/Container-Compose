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

@Suite("Project name precedence")
struct ProjectNameTests {

    /// A small valid compose document carrying an explicit `name:`.
    private func composeWithName() throws -> DockerCompose {
        try YAMLDecoder().decode(
            DockerCompose.self,
            from: "name: foo\nservices:\n  web:\n    image: x\n"
        )
    }

    /// A valid compose document with no top-level `name:`.
    private func composeWithoutName() throws -> DockerCompose {
        try YAMLDecoder().decode(
            DockerCompose.self,
            from: "services:\n  web:\n    image: x\n"
        )
    }

    @Test("--project-name override wins over compose name:")
    func overrideWinsOverComposeName() throws {
        let options = try ComposeProjectOptions.parse(["-p", "MYPROJ"])
        let compose = try composeWithName()

        #expect(options.projectName(for: compose) == "MYPROJ")
    }

    @Test("compose name: is used when no --project-name is given")
    func composeNameUsedWithoutOverride() throws {
        let options = try ComposeProjectOptions.parse([])
        let compose = try composeWithName()

        #expect(options.projectName(for: compose) == "foo")
    }

    @Test("falls back to sanitized directory name with neither override nor compose name:")
    func fallsBackToDirectoryName() throws {
        let cwd = "/tmp/Some.Project"
        let options = try ComposeProjectOptions.parse(["--cwd", cwd])
        let compose = try composeWithoutName()

        #expect(options.projectName(for: compose) == deriveProjectName(cwd: cwd))
    }
}

extension ProjectNameTests {

    /// Morris's #104 review ask: starting and stopping must resolve the same
    /// project name even when `-f` points outside the current directory.
    @Test("Default name derives from the compose file's directory, not the process cwd")
    func defaultNameFollowsComposeFileDirectory() throws {
        let composeNoName = try composeNoNameFixture()
        let a = try ComposeProjectOptions.parse(["-f", "/srv/myapp/compose.yml", "--cwd", "/Users/austin"])
        let b = try ComposeProjectOptions.parse(["-f", "/srv/myapp/compose.yml", "--cwd", "/tmp/somewhere-else"])
        #expect(a.projectName(for: composeNoName) == deriveProjectName(cwd: "/srv/myapp"))
        #expect(a.projectName(for: composeNoName) == b.projectName(for: composeNoName))
    }

    private func composeNoNameFixture() throws -> DockerCompose {
        try YAMLDecoder().decode(DockerCompose.self, from: "services:\n  web:\n    image: x\n")
    }
}
