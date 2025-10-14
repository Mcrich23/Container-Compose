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

@Suite("DockerCompose YAML Parsing Tests")
struct DockerComposeParsingTests {
    
    @Test("Parse basic docker-compose.yml with single service")
    func parseBasicCompose() throws {
        let yaml = """
        version: '3.8'
        services:
          web:
            image: nginx:latest
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.version == "3.8")
        #expect(compose.services.count == 1)
        #expect(compose.services["web"]?.image == "nginx:latest")
    }
    
    @Test("Parse compose file with project name")
    func parseComposeWithProjectName() throws {
        let yaml = """
        name: my-project
        services:
          app:
            image: alpine:latest
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.name == "my-project")
        #expect(compose.services["app"]?.image == "alpine:latest")
    }
    
    @Test("Parse compose with multiple services")
    func parseMultipleServices() throws {
        let yaml = """
        version: '3.8'
        services:
          web:
            image: nginx:latest
          db:
            image: postgres:14
          redis:
            image: redis:alpine
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services.count == 3)
        #expect(compose.services["web"]?.image == "nginx:latest")
        #expect(compose.services["db"]?.image == "postgres:14")
        #expect(compose.services["redis"]?.image == "redis:alpine")
    }
    
    @Test("Parse compose with volumes")
    func parseComposeWithVolumes() throws {
        let yaml = """
        version: '3.8'
        services:
          db:
            image: postgres:14
            volumes:
              - db-data:/var/lib/postgresql/data
        volumes:
          db-data:
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.volumes != nil)
        #expect(compose.volumes?["db-data"] != nil)
        #expect(compose.services["db"]?.volumes?.count == 1)
        #expect(compose.services["db"]?.volumes?.first == "db-data:/var/lib/postgresql/data")
    }
    
    @Test("Parse compose with networks")
    func parseComposeWithNetworks() throws {
        let yaml = """
        version: '3.8'
        services:
          web:
            image: nginx:latest
            networks:
              - frontend
        networks:
          frontend:
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.networks != nil)
        #expect(compose.networks?["frontend"] != nil)
        #expect(compose.services["web"]?.networks?.contains("frontend") == true)
    }
    
    @Test("Parse compose with environment variables")
    func parseComposeWithEnvironment() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            image: alpine:latest
            environment:
              DATABASE_URL: postgres://localhost/mydb
              DEBUG: "true"
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.environment != nil)
        #expect(compose.services["app"]?.environment?["DATABASE_URL"] == "postgres://localhost/mydb")
        #expect(compose.services["app"]?.environment?["DEBUG"] == "true")
    }
    
    @Test("Parse compose with ports")
    func parseComposeWithPorts() throws {
        let yaml = """
        version: '3.8'
        services:
          web:
            image: nginx:latest
            ports:
              - "8080:80"
              - "443:443"
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["web"]?.ports?.count == 2)
        #expect(compose.services["web"]?.ports?.contains("8080:80") == true)
        #expect(compose.services["web"]?.ports?.contains("443:443") == true)
    }
    
    @Test("Parse compose with depends_on")
    func parseComposeWithDependencies() throws {
        let yaml = """
        version: '3.8'
        services:
          web:
            image: nginx:latest
            depends_on:
              - db
          db:
            image: postgres:14
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["web"]?.depends_on?.contains("db") == true)
    }
    
    @Test("Parse compose with build context")
    func parseComposeWithBuild() throws {
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
        
        #expect(compose.services["app"]?.build != nil)
        #expect(compose.services["app"]?.build?.context == ".")
        #expect(compose.services["app"]?.build?.dockerfile == "Dockerfile")
    }
    
    @Test("Parse compose with command as array")
    func parseComposeWithCommandArray() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            image: alpine:latest
            command: ["sh", "-c", "echo hello"]
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.command?.count == 3)
        #expect(compose.services["app"]?.command?.first == "sh")
    }
    
    @Test("Parse compose with command as string")
    func parseComposeWithCommandString() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            image: alpine:latest
            command: "echo hello"
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.command?.count == 1)
        #expect(compose.services["app"]?.command?.first == "echo hello")
    }
    
    @Test("Parse compose with restart policy")
    func parseComposeWithRestartPolicy() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            image: alpine:latest
            restart: always
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.restart == "always")
    }
    
    @Test("Parse compose with container name")
    func parseComposeWithContainerName() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            image: alpine:latest
            container_name: my-custom-name
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.container_name == "my-custom-name")
    }
    
    @Test("Parse compose with working directory")
    func parseComposeWithWorkingDir() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            image: alpine:latest
            working_dir: /app
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.working_dir == "/app")
    }
    
    @Test("Parse compose with user")
    func parseComposeWithUser() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            image: alpine:latest
            user: "1000:1000"
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.user == "1000:1000")
    }
    
    @Test("Parse compose with privileged mode")
    func parseComposeWithPrivileged() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            image: alpine:latest
            privileged: true
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.privileged == true)
    }
    
    @Test("Parse compose with read-only filesystem")
    func parseComposeWithReadOnly() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            image: alpine:latest
            read_only: true
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.read_only == true)
    }
    
    @Test("Parse compose with stdin_open and tty")
    func parseComposeWithInteractiveFlags() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            image: alpine:latest
            stdin_open: true
            tty: true
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.stdin_open == true)
        #expect(compose.services["app"]?.tty == true)
    }
    
    @Test("Parse compose with hostname")
    func parseComposeWithHostname() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            image: alpine:latest
            hostname: my-host
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.hostname == "my-host")
    }
    
    @Test("Parse compose with platform")
    func parseComposeWithPlatform() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            image: alpine:latest
            platform: linux/amd64
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.platform == "linux/amd64")
    }
    
    @Test("Service must have image or build - should fail without either")
    func serviceRequiresImageOrBuild() throws {
        let yaml = """
        version: '3.8'
        services:
          app:
            restart: always
        """
        
        let decoder = YAMLDecoder()
        #expect(throws: Error.self) {
            try decoder.decode(DockerCompose.self, from: yaml)
        }
    }
}
