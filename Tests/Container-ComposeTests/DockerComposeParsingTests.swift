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

// Define the DockerCompose struct for testing purposes (normally imported from the main module)
struct DockerCompose: Codable {
    let version: String?
    let name: String?
    let services: [String: Service]
    let volumes: [String: Volume]?
    let networks: [String: Network]?
    let configs: [String: Config]?
    let secrets: [String: Secret]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        services = try container.decode([String: Service].self, forKey: .services)
        
        if let volumes = try container.decodeIfPresent([String: Optional<Volume>].self, forKey: .volumes) {
            let safeVolumes: [String : Volume] = volumes.mapValues { value in
                value ?? Volume()
            }
            self.volumes = safeVolumes
        } else {
            self.volumes = nil
        }
        networks = try container.decodeIfPresent([String: Network].self, forKey: .networks)
        configs = try container.decodeIfPresent([String: Config].self, forKey: .configs)
        secrets = try container.decodeIfPresent([String: Secret].self, forKey: .secrets)
    }
}

struct Service: Codable, Hashable {
    let image: String?
    let build: Build?
    let deploy: Deploy?
    let restart: String?
    let healthcheck: Healthcheck?
    let volumes: [String]?
    let environment: [String: String]?
    let env_file: [String]?
    let ports: [String]?
    let command: [String]?
    let depends_on: [String]?
    let user: String?
    let container_name: String?
    let networks: [String]?
    let hostname: String?
    let entrypoint: [String]?
    let privileged: Bool?
    let read_only: Bool?
    let working_dir: String?
    let platform: String?
    let configs: [ServiceConfig]?
    let secrets: [ServiceSecret]?
    let stdin_open: Bool?
    let tty: Bool?
    var dependedBy: [String] = []
    
    enum CodingKeys: String, CodingKey {
        case image, build, deploy, restart, healthcheck, volumes, environment, env_file, ports, command, depends_on, user,
             container_name, networks, hostname, entrypoint, privileged, read_only, working_dir, configs, secrets, stdin_open, tty, platform
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        build = try container.decodeIfPresent(Build.self, forKey: .build)
        deploy = try container.decodeIfPresent(Deploy.self, forKey: .deploy)
        
        guard image != nil || build != nil else {
            throw DecodingError.dataCorruptedError(forKey: .image, in: container, debugDescription: "Service must have either 'image' or 'build' specified.")
        }
        
        restart = try container.decodeIfPresent(String.self, forKey: .restart)
        healthcheck = try container.decodeIfPresent(Healthcheck.self, forKey: .healthcheck)
        volumes = try container.decodeIfPresent([String].self, forKey: .volumes)
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment)
        env_file = try container.decodeIfPresent([String].self, forKey: .env_file)
        ports = try container.decodeIfPresent([String].self, forKey: .ports)
        
        if let cmdArray = try? container.decodeIfPresent([String].self, forKey: .command) {
            command = cmdArray
        } else if let cmdString = try? container.decodeIfPresent(String.self, forKey: .command) {
            command = [cmdString]
        } else {
            command = nil
        }
        
        if let dependsOnString = try? container.decodeIfPresent(String.self, forKey: .depends_on) {
            depends_on = [dependsOnString]
        } else {
            depends_on = try container.decodeIfPresent([String].self, forKey: .depends_on)
        }
        user = try container.decodeIfPresent(String.self, forKey: .user)
        container_name = try container.decodeIfPresent(String.self, forKey: .container_name)
        networks = try container.decodeIfPresent([String].self, forKey: .networks)
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
        
        if let entrypointArray = try? container.decodeIfPresent([String].self, forKey: .entrypoint) {
            entrypoint = entrypointArray
        } else if let entrypointString = try? container.decodeIfPresent(String.self, forKey: .entrypoint) {
            entrypoint = [entrypointString]
        } else {
            entrypoint = nil
        }
        
        privileged = try container.decodeIfPresent(Bool.self, forKey: .privileged)
        read_only = try container.decodeIfPresent(Bool.self, forKey: .read_only)
        working_dir = try container.decodeIfPresent(String.self, forKey: .working_dir)
        configs = try container.decodeIfPresent([ServiceConfig].self, forKey: .configs)
        secrets = try container.decodeIfPresent([ServiceSecret].self, forKey: .secrets)
        stdin_open = try container.decodeIfPresent(Bool.self, forKey: .stdin_open)
        tty = try container.decodeIfPresent(Bool.self, forKey: .tty)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
    }
}

struct Volume: Codable, Hashable {}
struct Network: Codable, Hashable {}
struct Config: Codable, Hashable {}
struct Secret: Codable, Hashable {}
struct Build: Codable, Hashable {
    let context: String?
    let dockerfile: String?
}
struct Deploy: Codable, Hashable {}
struct Healthcheck: Codable, Hashable {}
struct ServiceConfig: Codable, Hashable {}
struct ServiceSecret: Codable, Hashable {}
