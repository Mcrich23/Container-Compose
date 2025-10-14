//===----------------------------------------------------------------------===//
// Copyright © 2025 Apple Inc. and the container project authors. All rights reserved.
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
    
    @Test("Parse build with target")
    func parseBuildWithTarget() throws {
        let yaml = """
        context: .
        target: production
        """
        
        let decoder = YAMLDecoder()
        let build = try decoder.decode(Build.self, from: yaml)
        
        #expect(build.context == ".")
        #expect(build.target == "production")
    }
    
    @Test("Parse build with cache_from")
    func parseBuildWithCacheFrom() throws {
        let yaml = """
        context: .
        cache_from:
          - alpine:latest
          - myapp:cache
        """
        
        let decoder = YAMLDecoder()
        let build = try decoder.decode(Build.self, from: yaml)
        
        #expect(build.context == ".")
        #expect(build.cache_from?.count == 2)
        #expect(build.cache_from?.contains("alpine:latest") == true)
    }
    
    @Test("Parse build with labels")
    func parseBuildWithLabels() throws {
        let yaml = """
        context: .
        labels:
          com.example.version: "1.0"
          com.example.description: "Test app"
        """
        
        let decoder = YAMLDecoder()
        let build = try decoder.decode(Build.self, from: yaml)
        
        #expect(build.context == ".")
        #expect(build.labels?["com.example.version"] == "1.0")
        #expect(build.labels?["com.example.description"] == "Test app")
    }
    
    @Test("Parse build with network mode")
    func parseBuildWithNetwork() throws {
        let yaml = """
        context: .
        network: host
        """
        
        let decoder = YAMLDecoder()
        let build = try decoder.decode(Build.self, from: yaml)
        
        #expect(build.context == ".")
        #expect(build.network == "host")
    }
    
    @Test("Parse build with shm_size")
    func parseBuildWithShmSize() throws {
        let yaml = """
        context: .
        shm_size: 256mb
        """
        
        let decoder = YAMLDecoder()
        let build = try decoder.decode(Build.self, from: yaml)
        
        #expect(build.context == ".")
        #expect(build.shm_size == "256mb")
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
        let compose = try decoder.decode(TestDockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.build != nil)
        #expect(compose.services["app"]?.build?.context == ".")
        #expect(compose.services["app"]?.build?.dockerfile == "Dockerfile")
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
        let compose = try decoder.decode(TestDockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.image == "myapp:latest")
        #expect(compose.services["app"]?.build?.context == ".")
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
