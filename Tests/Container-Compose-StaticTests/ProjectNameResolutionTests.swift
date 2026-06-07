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
@testable import ContainerComposeCore

@Suite("Project Name Resolution Tests")
struct ProjectNameResolutionTests {

    @Test("Interpolate variable with default in 'name' field when variable is unset")
    func interpolateNameFieldWithDefault() {
        // Regression: a literal "${VAR:-default}" project name produced invalid container names.
        // Uses a unique variable name so the real process environment cannot interfere.
        let result = resolveProjectName(
            flagValue: nil,
            composeName: "${CC_TEST_PROJECT_NAME_UNSET:-sample_project}",
            envVars: [:],
            cwd: "/tmp/somedir",
            processEnv: [:]
        )

        #expect(result == "sample_project")
    }

    @Test("Interpolate variable in 'name' field from .env file")
    func interpolateNameFieldFromEnvFile() {
        let result = resolveProjectName(
            flagValue: nil,
            composeName: "${CC_TEST_PROJECT_NAME_UNSET:-fallback}",
            envVars: ["CC_TEST_PROJECT_NAME_UNSET": "from_env_file"],
            cwd: "/tmp/somedir",
            processEnv: [:]
        )

        #expect(result == "from_env_file")
    }

    @Test("Literal 'name' field is used as-is")
    func literalNameField() {
        let result = resolveProjectName(
            flagValue: nil,
            composeName: "my-project",
            envVars: [:],
            cwd: "/tmp/somedir",
            processEnv: [:]
        )

        #expect(result == "my-project")
    }

    @Test("COMPOSE_PROJECT_NAME overrides 'name' field")
    func composeProjectNameOverridesNameField() {
        let result = resolveProjectName(
            flagValue: nil,
            composeName: "from-compose-file",
            envVars: [:],
            cwd: "/tmp/somedir",
            processEnv: ["COMPOSE_PROJECT_NAME": "from-process-env"]
        )

        #expect(result == "from-process-env")
    }

    @Test("COMPOSE_PROJECT_NAME from .env file is used when no 'name' field")
    func composeProjectNameFromEnvFile() {
        let result = resolveProjectName(
            flagValue: nil,
            composeName: nil,
            envVars: ["COMPOSE_PROJECT_NAME": "from-env-file"],
            cwd: "/tmp/somedir",
            processEnv: [:]
        )

        #expect(result == "from-env-file")
    }

    @Test("Process environment beats .env file for COMPOSE_PROJECT_NAME")
    func processEnvBeatsEnvFile() {
        let result = resolveProjectName(
            flagValue: nil,
            composeName: nil,
            envVars: ["COMPOSE_PROJECT_NAME": "from-env-file"],
            cwd: "/tmp/somedir",
            processEnv: ["COMPOSE_PROJECT_NAME": "from-process-env"]
        )

        #expect(result == "from-process-env")
    }

    @Test("Project name flag beats environment and 'name' field")
    func flagBeatsEverything() {
        let result = resolveProjectName(
            flagValue: "from-flag",
            composeName: "from-compose-file",
            envVars: ["COMPOSE_PROJECT_NAME": "from-env-file"],
            cwd: "/tmp/somedir",
            processEnv: ["COMPOSE_PROJECT_NAME": "from-process-env"]
        )

        #expect(result == "from-flag")
    }

    @Test("Falls back to directory name when nothing else is provided")
    func fallsBackToDirectoryName() {
        let result = resolveProjectName(
            flagValue: nil,
            composeName: nil,
            envVars: [:],
            cwd: "/tmp/my.project",
            processEnv: [:]
        )

        #expect(result == "my_project")
    }

    @Test("Empty COMPOSE_PROJECT_NAME is ignored")
    func emptyComposeProjectNameIsIgnored() {
        let result = resolveProjectName(
            flagValue: nil,
            composeName: "from-compose-file",
            envVars: [:],
            cwd: "/tmp/somedir",
            processEnv: ["COMPOSE_PROJECT_NAME": ""]
        )

        #expect(result == "from-compose-file")
    }
}
