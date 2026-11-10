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

@Suite("Build Configuration Tests")
struct BuildConfigurationTests {
    
    @Test("Parse build with context only")
    func parseBuildWithContextOnly() throws {
        let yaml = """
        context: .
        """
        
        let decoder = YAMLDecoder()
        let build = try decoder.decode(Build.self, from: yaml)
        
        #expect(build.context == ".")
        #expect(build.dockerfile == nil)
    }
    
    @Test("Parse build with context and dockerfile")
    func parseBuildWithContextAndDockerfile() throws {
        let yaml = """
        context: ./app
        dockerfile: Dockerfile.prod
        """
        
        let decoder = YAMLDecoder()
        let build = try decoder.decode(Build.self, from: yaml)
        
        #expect(build.context == "./app")
        #expect(build.dockerfile == "Dockerfile.prod")
    }
    
    @Test("Parse build with build args")
    func parseBuildWithBuildArgs() throws {
        let yaml = """
        context: .
        args:
          NODE_VERSION: "18"
          ENV: "production"
        """

        let decoder = YAMLDecoder()
        let build = try decoder.decode(Build.self, from: yaml)

        #expect(build.context == ".")
        #expect(build.args?["NODE_VERSION"] == "18")
        #expect(build.args?["ENV"] == "production")
    }

    // Compose allows `build.args` in list form (`- KEY=VALUE`), not only the
    // map form above. Previously the list form threw
    // `DecodingError.typeMismatch` and crashed the whole `up` (see #136).
    @Test("Parse build args in list form (KEY=VALUE)")
    func parseBuildArgsListForm() throws {
        let yaml = """
        context: nginx
        args:
          - DIR=development
        """

        let decoder = YAMLDecoder()
        let build = try decoder.decode(Build.self, from: yaml)

        #expect(build.context == "nginx")
        #expect(build.args?["DIR"] == "development")
    }

    
    // Exact repro from #136: a service using the list form of `build.args`
    // (alongside other fields) used to crash the whole `up` at decode time.
    @Test("Regression #136: full service with list-form build args decodes")
    func regressionListFormBuildArgsInService() throws {
        let yaml = """
        services:
          nginx:
            container_name: proxy
            build:
              context: nginx
              args:
                - DIR=development
        """

        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        let build = try #require(compose.services["nginx"]??.build)

        #expect(build.context == "nginx")
        #expect(build.args?["DIR"] == "development")
    }

    // A build-arg value that itself contains `=` must split on the FIRST `=` only,
    // so the remainder is preserved verbatim.
    @Test("List-form build arg value keeps internal '=' characters")
    func listFormBuildArgValueKeepsEquals() throws {
        let yaml = """
        context: .
        args:
          - DATABASE_URL=postgres://u:p@h/db?sslmode=require
        """

        let decoder = YAMLDecoder()
        let build = try decoder.decode(Build.self, from: yaml)

        #expect(build.args?["DATABASE_URL"] == "postgres://u:p@h/db?sslmode=require")
    }

    @Test("Service with build configuration")
    func serviceWithBuildConfiguration() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            build:
              context: .
              dockerfile: Dockerfile
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.build != nil)
        #expect(compose.services["app"]??.build?.context == ".")
        #expect(compose.services["app"]??.build?.dockerfile == "Dockerfile")
    }
    
    @Test("Service with both image and build")
    func serviceWithImageAndBuild() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            image: myapp:latest
            build:
              context: .
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.image == "myapp:latest")
        #expect(compose.services["app"]??.build?.context == ".")
    }
    
    @Test("Relative context path resolution")
    func relativeContextPathResolution() {
        let context = "./app"
        let cwd = "/home/user/project"
        
        let fullPath: String
        if context.starts(with: "/") || context.starts(with: "~") {
            fullPath = context
        } else {
            fullPath = cwd + "/" + context
        }
        
        #expect(fullPath == "/home/user/project/./app")
    }
    
    @Test("Absolute context path")
    func absoluteContextPath() {
        let context = "/absolute/path/to/build"
        
        #expect(context.starts(with: "/") == true)
    }
}

// Test helper structs
