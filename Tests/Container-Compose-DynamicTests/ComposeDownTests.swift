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

@Suite("Compose Down Tests")
struct ComposeDownTests {

    @Test("What goes up must come down - container_name")
      func testUpAndDownContainerName() async throws  {
        let yaml = DockerComposeYamlFiles.dockerComposeYaml1
        
        let tempLocation = URL.temporaryDirectory.appending(path: "Container-Compose_Tests_\(UUID().uuidString)/docker-compose.yaml")
        let tempBase = tempLocation.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: tempLocation.deletingLastPathComponent(), withIntermediateDirectories: true)
        try yaml.write(to: tempLocation, atomically: false, encoding: .utf8)
        let folderName = tempBase.lastPathComponent
        
        var composeUp = try ComposeUp.parse(["-d", "--cwd", tempBase.path(percentEncoded: false)])
        try await composeUp.run()

        var containers = try await ClientContainer.list()
            .filter({
                $0.configuration.id.contains(folderName)
            })
        
        #expect(containers.count == 1, "Expected 1 containers to be running, found \(containers.count)")
        //#expect(containers[0].configuration.names.contains("/custom_nginx"), "Expected container to have name /custom_nginx, found \(containers[0].configuration.names)")
    
        var composeDown = try ComposeDown.parse(["--cwd", tempBase.path(percentEncoded: false)])
        try await composeDown.run()

        containers = try await ClientContainer.list()
            .filter({
                $0.configuration.id.contains(folderName)
            })
        
        #expect(containers.count == 0, "Expected no containers to be running, found \(containers.count)")
    }

}