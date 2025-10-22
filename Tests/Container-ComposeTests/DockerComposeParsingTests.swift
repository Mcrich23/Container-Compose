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

@Suite("DockerCompose YAML Parsing Tests")
struct DockerComposeParsingTests {
    
    // MARK: - Basic Parsing Tests
    
    @Test("Parse minimal docker-compose with single service")
    func parseMinimalCompose() throws {
        let yaml = """
        services:
          web:
            image: nginx:latest
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services.count == 1)
        #expect(compose.services["web"]??.image == "nginx:latest")
    }
    
    @Test("Parse compose with version field")
    func parseComposeWithVersion() throws {
        let yaml = """
        version: '3.8'
        services:
          web:
            image: nginx:latest
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.version == "3.8")
        #expect(compose.services["web"]??.image == "nginx:latest")
    }
    
    @Test("Parse compose with project name")
    func parseComposeWithName() throws {
        let yaml = """
        name: my-project
        services:
          app:
            image: alpine:latest
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.name == "my-project")
        #expect(compose.services["app"]??.image == "alpine:latest")
    }
    
    @Test("Parse compose with multiple services")
    func parseMultipleServices() throws {
        let yaml = """
        services:
          web:
            image: nginx:latest
          db:
            image: postgres:14
          cache:
            image: redis:alpine
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services.count == 3)
        #expect(compose.services["web"]??.image == "nginx:latest")
        #expect(compose.services["db"]??.image == "postgres:14")
        #expect(compose.services["cache"]??.image == "redis:alpine")
    }
    
    // MARK: - Service Image and Build Tests
    
    @Test("Parse service with build context")
    func parseServiceWithBuild() throws {
        let yaml = """
        services:
          app:
            build:
              context: ./app
              dockerfile: Dockerfile
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.build != nil)
        #expect(compose.services["app"]??.build?.context == "./app")
        #expect(compose.services["app"]??.build?.dockerfile == "Dockerfile")
    }
    
    @Test("Parse service with build and image")
    func parseServiceWithBuildAndImage() throws {
        let yaml = """
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
    
    @Test("Parse service with build args")
    func parseServiceWithBuildArgs() throws {
        let yaml = """
        services:
          app:
            build:
              context: .
              args:
                NODE_ENV: production
                VERSION: 1.0.0
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.build?.args?["NODE_ENV"] == "production")
        #expect(compose.services["app"]??.build?.args?["VERSION"] == "1.0.0")
    }
    
    @Test("Service without image or build should fail")
    func serviceRequiresImageOrBuild() throws {
        let yaml = """
        services:
          app:
            restart: always
        """
        
        let decoder = YAMLDecoder()
        #expect(throws: Error.self) {
            try decoder.decode(DockerCompose.self, from: yaml)
        }
    }
    
    // MARK: - Service Configuration Tests
    
    @Test("Parse service with environment variables")
    func parseServiceWithEnvironment() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            environment:
              DATABASE_URL: postgres://localhost/mydb
              DEBUG: "true"
              PORT: "8080"
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.environment?["DATABASE_URL"] == "postgres://localhost/mydb")
        #expect(compose.services["app"]??.environment?["DEBUG"] == "true")
        #expect(compose.services["app"]??.environment?["PORT"] == "8080")
    }
    
    @Test("Parse service with env_file")
    func parseServiceWithEnvFile() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            env_file:
              - .env
              - .env.local
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.env_file?.count == 2)
        #expect(compose.services["app"]??.env_file?.contains(".env") == true)
        #expect(compose.services["app"]??.env_file?.contains(".env.local") == true)
    }
    
    @Test("Parse service with ports")
    func parseServiceWithPorts() throws {
        let yaml = """
        services:
          web:
            image: nginx:latest
            ports:
              - "8080:80"
              - "443:443"
              - "3000"
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["web"]??.ports?.count == 3)
        #expect(compose.services["web"]??.ports?.contains("8080:80") == true)
        #expect(compose.services["web"]??.ports?.contains("443:443") == true)
        #expect(compose.services["web"]??.ports?.contains("3000") == true)
    }
    
    @Test("Parse service with volumes")
    func parseServiceWithVolumes() throws {
        let yaml = """
        services:
          db:
            image: postgres:14
            volumes:
              - db-data:/var/lib/postgresql/data
              - ./config:/etc/config:ro
              - /host/path:/container/path
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["db"]??.volumes?.count == 3)
        #expect(compose.services["db"]??.volumes?.contains("db-data:/var/lib/postgresql/data") == true)
        #expect(compose.services["db"]??.volumes?.contains("./config:/etc/config:ro") == true)
        #expect(compose.services["db"]??.volumes?.contains("/host/path:/container/path") == true)
    }
    
    @Test("Parse service with depends_on")
    func parseServiceWithDependsOn() throws {
        let yaml = """
        services:
          web:
            image: nginx:latest
            depends_on:
              - db
              - cache
          db:
            image: postgres:14
          cache:
            image: redis:alpine
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["web"]??.depends_on?.count == 2)
        #expect(compose.services["web"]??.depends_on?.contains("db") == true)
        #expect(compose.services["web"]??.depends_on?.contains("cache") == true)
    }
    
    @Test("Parse service with single depends_on as string")
    func parseServiceWithSingleDependsOn() throws {
        let yaml = """
        services:
          web:
            image: nginx:latest
            depends_on: db
          db:
            image: postgres:14
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["web"]??.depends_on?.count == 1)
        #expect(compose.services["web"]??.depends_on?.contains("db") == true)
    }
    
    // MARK: - Service Command and Entrypoint Tests
    
    @Test("Parse service with command as array")
    func parseServiceWithCommandArray() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            command: ["sh", "-c", "echo hello"]
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.command?.count == 3)
        #expect(compose.services["app"]??.command?[0] == "sh")
        #expect(compose.services["app"]??.command?[1] == "-c")
        #expect(compose.services["app"]??.command?[2] == "echo hello")
    }
    
    @Test("Parse service with command as string")
    func parseServiceWithCommandString() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            command: "python app.py"
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.command?.count == 1)
        #expect(compose.services["app"]??.command?[0] == "python app.py")
    }
    
    @Test("Parse service with entrypoint as array")
    func parseServiceWithEntrypointArray() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            entrypoint: ["/bin/sh", "-c"]
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.entrypoint?.count == 2)
        #expect(compose.services["app"]??.entrypoint?[0] == "/bin/sh")
        #expect(compose.services["app"]??.entrypoint?[1] == "-c")
    }
    
    @Test("Parse service with entrypoint as string")
    func parseServiceWithEntrypointString() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            entrypoint: "/bin/bash"
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.entrypoint?.count == 1)
        #expect(compose.services["app"]??.entrypoint?[0] == "/bin/bash")
    }
    
    // MARK: - Service Container Configuration Tests
    
    @Test("Parse service with container_name")
    func parseServiceWithContainerName() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            container_name: my-custom-container
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.container_name == "my-custom-container")
    }
    
    @Test("Parse service with hostname")
    func parseServiceWithHostname() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            hostname: myapp.local
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.hostname == "myapp.local")
    }
    
    @Test("Parse service with user")
    func parseServiceWithUser() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            user: "1000:1000"
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.user == "1000:1000")
    }
    
    @Test("Parse service with working_dir")
    func parseServiceWithWorkingDir() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            working_dir: /app
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.working_dir == "/app")
    }
    
    @Test("Parse service with restart policy")
    func parseServiceWithRestartPolicy() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            restart: always
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.restart == "always")
    }
    
    // MARK: - Service Boolean Flags Tests
    
    @Test("Parse service with privileged flag")
    func parseServiceWithPrivileged() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            privileged: true
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.privileged == true)
    }
    
    @Test("Parse service with read_only flag")
    func parseServiceWithReadOnly() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            read_only: true
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.read_only == true)
    }
    
    @Test("Parse service with stdin_open flag")
    func parseServiceWithStdinOpen() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            stdin_open: true
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.stdin_open == true)
    }
    
    @Test("Parse service with tty flag")
    func parseServiceWithTty() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            tty: true
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.tty == true)
    }
    
    @Test("Parse service with all boolean flags")
    func parseServiceWithAllBooleanFlags() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            privileged: true
            read_only: true
            stdin_open: true
            tty: true
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.privileged == true)
        #expect(compose.services["app"]??.read_only == true)
        #expect(compose.services["app"]??.stdin_open == true)
        #expect(compose.services["app"]??.tty == true)
    }
    
    // MARK: - Service Platform Tests
    
    @Test("Parse service with platform")
    func parseServiceWithPlatform() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            platform: linux/amd64
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.platform == "linux/amd64")
    }
    
    // MARK: - Top-Level Volumes Tests
    
    @Test("Parse compose with top-level volumes")
    func parseComposeWithVolumes() throws {
        let yaml = """
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
    }
    
    @Test("Parse compose with named volume")
    func parseComposeWithNamedVolume() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
        volumes:
          data:
            name: my-data-volume
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.volumes?["data"]??.name == "my-data-volume")
    }
    
    // MARK: - Top-Level Networks Tests
    
    @Test("Parse compose with top-level networks")
    func parseComposeWithNetworks() throws {
        let yaml = """
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
        #expect(compose.services["web"]??.networks?.contains("frontend") == true)
    }
    
    @Test("Parse compose with network driver")
    func parseComposeWithNetworkDriver() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
        networks:
          custom:
            driver: bridge
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.networks?["custom"]??.driver == "bridge")
    }
    
    @Test("Parse compose with external network")
    func parseComposeWithExternalNetwork() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            networks:
              - existing-network
        networks:
          existing-network:
            external: true
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.networks?["existing-network"]??.external?.isExternal == true)
    }
    
    // MARK: - Service Networks Tests
    
    @Test("Parse service with multiple networks")
    func parseServiceWithMultipleNetworks() throws {
        let yaml = """
        services:
          app:
            image: alpine:latest
            networks:
              - frontend
              - backend
        networks:
          frontend:
          backend:
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.networks?.count == 2)
        #expect(compose.services["app"]??.networks?.contains("frontend") == true)
        #expect(compose.services["app"]??.networks?.contains("backend") == true)
    }
    
    // MARK: - Complex Integration Tests
    
    @Test("Parse complete compose file with all features")
    func parseCompleteComposeFile() throws {
        let yaml = """
        version: '3.8'
        name: my-app
        services:
          web:
            image: nginx:latest
            container_name: web-server
            ports:
              - "8080:80"
            networks:
              - frontend
            depends_on:
              - api
            environment:
              NGINX_HOST: localhost
              NGINX_PORT: "80"
            volumes:
              - ./nginx.conf:/etc/nginx/nginx.conf:ro
          api:
            build:
              context: ./api
              dockerfile: Dockerfile
              args:
                NODE_ENV: production
            image: myapp-api:latest
            ports:
              - "3000:3000"
            networks:
              - frontend
              - backend
            depends_on:
              - db
            environment:
              DATABASE_URL: postgres://db:5432/myapp
              REDIS_URL: redis://cache:6379
            env_file:
              - .env
            working_dir: /app
            user: "1000:1000"
            restart: unless-stopped
          db:
            image: postgres:14
            container_name: postgres-db
            volumes:
              - db-data:/var/lib/postgresql/data
            networks:
              - backend
            environment:
              POSTGRES_PASSWORD: secret
              POSTGRES_DB: myapp
          cache:
            image: redis:alpine
            networks:
              - backend
        networks:
          frontend:
            driver: bridge
          backend:
            driver: bridge
        volumes:
          db-data:
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        // Verify top-level fields
        #expect(compose.version == "3.8")
        #expect(compose.name == "my-app")
        #expect(compose.services.count == 4)
        #expect(compose.networks?.count == 2)
        #expect(compose.volumes?.count == 1)
        
        // Verify web service
        #expect(compose.services["web"]??.image == "nginx:latest")
        #expect(compose.services["web"]??.container_name == "web-server")
        #expect(compose.services["web"]??.ports?.count == 1)
        #expect(compose.services["web"]??.networks?.count == 1)
        #expect(compose.services["web"]??.depends_on?.contains("api") == true)
        
        // Verify api service
        #expect(compose.services["api"]??.build != nil)
        #expect(compose.services["api"]??.image == "myapp-api:latest")
        #expect(compose.services["api"]??.networks?.count == 2)
        #expect(compose.services["api"]??.working_dir == "/app")
        #expect(compose.services["api"]??.user == "1000:1000")
        #expect(compose.services["api"]??.restart == "unless-stopped")
        
        // Verify db service
        #expect(compose.services["db"]??.image == "postgres:14")
        #expect(compose.services["db"]??.volumes?.count == 1)
        
        // Verify cache service
        #expect(compose.services["cache"]??.image == "redis:alpine")
    }
    
    @Test("Parse topological sort of services with dependencies")
    func parseAndSortServiceDependencies() throws {
        let yaml = """
        services:
          web:
            image: nginx:latest
            depends_on:
              - api
          api:
            image: node:latest
            depends_on:
              - db
          db:
            image: postgres:14
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        let services: [(serviceName: String, service: Service)] = compose.services.compactMap { serviceName, service in
            guard let service else { return nil }
            return (serviceName, service)
        }
        
        let sorted = try Service.topoSortConfiguredServices(services)
        
        // db should come before api, api should come before web
        let sortedNames = sorted.map { $0.serviceName }
        let dbIndex = sortedNames.firstIndex(of: "db")!
        let apiIndex = sortedNames.firstIndex(of: "api")!
        let webIndex = sortedNames.firstIndex(of: "web")!
        
        #expect(dbIndex < apiIndex)
        #expect(apiIndex < webIndex)
    }
}
