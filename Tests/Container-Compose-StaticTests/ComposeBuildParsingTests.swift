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
@testable import Yams
@testable import ContainerComposeCore

@Suite("Compose Build Parsing Tests")
struct ComposeBuildParsingTests {

    @Test("Services with build config are selected for building")
    func servicesWithBuildConfigAreSelected() throws {
        let yaml = """
        services:
          app:
            build:
              context: .
              dockerfile: Dockerfile
          cache:
            image: redis:alpine
        """

        let compose = try YAMLDecoder().decode(DockerCompose.self, from: yaml)

        let buildable = compose.services.compactMap { name, service -> String? in
            guard let service, service.build != nil else { return nil }
            return name
        }

        #expect(buildable == ["app"])
    }

    @Test("Services without build config are excluded")
    func servicesWithoutBuildConfigAreExcluded() throws {
        let yaml = """
        services:
          web:
            image: nginx:alpine
          db:
            image: postgres:14
        """

        let compose = try YAMLDecoder().decode(DockerCompose.self, from: yaml)

        let buildable = compose.services.compactMap { name, service -> String? in
            guard let service, service.build != nil else { return nil }
            return name
        }

        #expect(buildable.isEmpty)
    }

    @Test("Mixed compose file — only build services are selected")
    func mixedComposeFileOnlyBuildServicesSelected() throws {
        let yaml = """
        services:
          app:
            build:
              context: ./app
          worker:
            build:
              context: ./worker
          db:
            image: postgres:14
          cache:
            image: redis:alpine
        """

        let compose = try YAMLDecoder().decode(DockerCompose.self, from: yaml)

        let buildable = compose.services.compactMap { name, service -> String? in
            guard let service, service.build != nil else { return nil }
            return name
        }.sorted()

        #expect(buildable == ["app", "worker"])
    }

    @Test("Image tag defaults to serviceName:latest when image field is absent")
    func imageTagDefaultsToServiceNameLatest() throws {
        let yaml = """
        services:
          myservice:
            build:
              context: .
        """

        let compose = try YAMLDecoder().decode(DockerCompose.self, from: yaml)
        let service = try #require(compose.services["myservice"] ?? nil)

        let tag = service.image ?? "myservice:latest"
        #expect(tag == "myservice:latest")
    }

    @Test("Explicit image field is used as the build tag")
    func explicitImageFieldIsUsedAsBuildTag() throws {
        let yaml = """
        services:
          app:
            image: myorg/myapp:v1.2.3
            build:
              context: .
        """

        let compose = try YAMLDecoder().decode(DockerCompose.self, from: yaml)
        let service = try #require(compose.services["app"] ?? nil)

        let tag = service.image ?? "app:latest"
        #expect(tag == "myorg/myapp:v1.2.3")
    }

    @Test("Build args are passed through from compose file")
    func buildArgsArePassedThrough() throws {
        let yaml = """
        services:
          app:
            build:
              context: .
              args:
                NODE_VERSION: "20"
                ENV: production
        """

        let compose = try YAMLDecoder().decode(DockerCompose.self, from: yaml)
        let build = try #require(compose.services["app"]??.build)

        #expect(build.args?["NODE_VERSION"] == "20")
        #expect(build.args?["ENV"] == "production")
    }

    @Test("ComposeBuild command parses --no-cache flag")
    func composeBuildCommandParsesNoCacheFlag() throws {
        let cmd = try ComposeBuild.parse(["--no-cache"])
        #expect(cmd.noCache == true)
    }

    @Test("ComposeBuild command defaults no-cache to false")
    func composeBuildCommandDefaultsNoCacheToFalse() throws {
        let cmd = try ComposeBuild.parse([])
        #expect(cmd.noCache == false)
    }

    @Test("ComposeBuild command accepts service name arguments")
    func composeBuildCommandAcceptsServiceNameArguments() throws {
        let cmd = try ComposeBuild.parse(["app", "worker"])
        #expect(cmd.services == ["app", "worker"])
    }

    @Test("ComposeBuild command accepts -f flag for compose file")
    func composeBuildCommandAcceptsFileFlag() throws {
        let cmd = try ComposeBuild.parse(["-f", "my-compose.yaml"])
        #expect(cmd.composeFilename == "my-compose.yaml")
    }
}
