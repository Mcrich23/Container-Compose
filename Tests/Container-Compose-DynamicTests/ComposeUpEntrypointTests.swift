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

/// End-to-end check for the entrypoint+command translation. The exact pattern
/// from issue #77: `entrypoint: ["/bin/sh", "-c"]` plus a multi-line command
/// that depends on the script reaching `sh` as a single argument.
@Suite("Compose Up Tests - Entrypoint + Command", .containerDependent, .serialized)
struct ComposeUpEntrypointTests {

    func stopInstance(location: URL) async throws {
        var composeDown = try ComposeDown.parse(["--cwd", location.path(percentEncoded: false)])
        try await composeDown.run()
    }

    @Test("sh -c + multi-line command runs the script (regression for #77)")
    func shHeredocCommandRuns() async throws {
        // The multi-line command exits 0 only when the script is delivered intact.
        // On the broken code path, `command:` is silently dropped (mutually
        // exclusive with `entrypoint:`), so the container would either fail to
        // start or sit idle.
        let yaml = """
        name: cc-entrypoint-test
        services:
          probe:
            image: alpine:latest
            entrypoint: ["/bin/sh", "-c"]
            command:
              - |
                echo first-line
                echo second-line
                sleep 30
        """
        let project = try DockerComposeYamlFiles.copyYamlToTemporaryLocation(yaml: yaml)

        var composeUp = try ComposeUp.parse([
            "-d", "--cwd", project.base.path(percentEncoded: false),
        ])
        try await composeUp.run()

        let containerID = "cc-entrypoint-test-probe"
        let client = ContainerClient()
        let container = try? await client.get(id: containerID)

        // On the buggy code, `command:` is dropped and the container's only
        // arg is `--entrypoint /bin/sh -c` (positional, malformed) — sh exits
        // immediately. So a container that's `running` after `up` proves the
        // command actually got through.
        #expect(container != nil, "expected container '\(containerID)' to exist")
        #expect(container?.status == .running,
                "container should be running — broken code drops `command:` and sh exits with no script")

        try? await stopInstance(location: project.base)
    }
}
