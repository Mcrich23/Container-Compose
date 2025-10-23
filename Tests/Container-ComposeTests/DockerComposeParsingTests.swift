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
    // MARK: File Snippets
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
        #expect(compose.services["web"]??.image == "nginx:latest")
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
        #expect(compose.services["app"]??.image == "alpine:latest")
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
        #expect(compose.services["web"]??.image == "nginx:latest")
        #expect(compose.services["db"]??.image == "postgres:14")
        #expect(compose.services["redis"]??.image == "redis:alpine")
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
        #expect(compose.services["db"]??.volumes?.count == 1)
        #expect(compose.services["db"]??.volumes?.first == "db-data:/var/lib/postgresql/data")
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
        #expect(compose.services["web"]??.networks?.contains("frontend") == true)
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
        
        #expect(compose.services["app"]??.environment != nil)
        #expect(compose.services["app"]??.environment?["DATABASE_URL"] == "postgres://localhost/mydb")
        #expect(compose.services["app"]??.environment?["DEBUG"] == "true")
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
        
        #expect(compose.services["web"]??.ports?.count == 2)
        #expect(compose.services["web"]??.ports?.contains("8080:80") == true)
        #expect(compose.services["web"]??.ports?.contains("443:443") == true)
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
        
        #expect(compose.services["web"]??.depends_on?.contains("db") == true)
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
        
        #expect(compose.services["app"]??.build != nil)
        #expect(compose.services["app"]??.build?.context == ".")
        #expect(compose.services["app"]??.build?.dockerfile == "Dockerfile")
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
        
        #expect(compose.services["app"]??.command?.count == 3)
        #expect(compose.services["app"]??.command?.first == "sh")
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
        
        #expect(compose.services["app"]??.command?.count == 1)
        #expect(compose.services["app"]??.command?.first == "echo hello")
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
        
        #expect(compose.services["app"]??.restart == "always")
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
        
        #expect(compose.services["app"]??.container_name == "my-custom-name")
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
        
        #expect(compose.services["app"]??.working_dir == "/app")
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
        
        #expect(compose.services["app"]??.user == "1000:1000")
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
        
        #expect(compose.services["app"]??.privileged == true)
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
        
        #expect(compose.services["app"]??.read_only == true)
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
        
        #expect(compose.services["app"]??.stdin_open == true)
        #expect(compose.services["app"]??.tty == true)
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
        
        #expect(compose.services["app"]??.hostname == "my-host")
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
        
        #expect(compose.services["app"]??.platform == "linux/amd64")
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
    
    // MARK: Full Files
    @Test("Parse WordPress with MySQL compose file")
    func parseWordPressCompose() throws {
        let yaml = Self.dockerComposeYaml1
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services.count == 2)
        #expect(compose.services["wordpress"] != nil)
        #expect(compose.services["db"] != nil)
        #expect(compose.volumes?.count == 2)
        #expect(compose.services["wordpress"]??.depends_on?.contains("db") == true)
    }
    
    @Test("Parse three-tier web application")
    func parseThreeTierApp() throws {
        let yaml = Self.dockerComposeYaml2
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.name == "webapp")
        #expect(compose.services.count == 4)
        #expect(compose.networks?.count == 2)
        #expect(compose.volumes?.count == 1)
    }
    
    @Test("Parse microservices architecture")
    func parseMicroservicesCompose() throws {
        let yaml = Self.dockerComposeYaml3
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services.count == 5)
        #expect(compose.services["api-gateway"]??.depends_on?.count == 3)
    }
    
    @Test("Parse development environment with build")
    func parseDevelopmentEnvironment() throws {
        let yaml = Self.dockerComposeYaml4
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.build != nil)
        #expect(compose.services["app"]??.build?.context == ".")
        #expect(compose.services["app"]??.volumes?.count == 2)
    }
    
    @Test("Parse compose with secrets and configs")
    func parseComposeWithSecretsAndConfigs() throws {
        let yaml = Self.dockerComposeYaml5
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.configs != nil)
        #expect(compose.secrets != nil)
    }
    
    @Test("Parse compose with healthchecks and restart policies")
    func parseComposeWithHealthchecksAndRestart() throws {
        let yaml = Self.dockerComposeYaml6
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["web"]??.restart == "unless-stopped")
        #expect(compose.services["web"]??.healthcheck != nil)
        #expect(compose.services["db"]??.restart == "always")
    }
    
    @Test("Parse compose with complex dependency chain")
    func parseComplexDependencyChain() throws {
        let yaml = Self.dockerComposeYaml6
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services.count == 4)
        
        // Test dependency resolution
        let services: [(String, Service)] = compose.services.compactMap({ serviceName, service in
            guard let service else { return nil }
            return (serviceName, service)
        })
        let sorted = try Service.topoSortConfiguredServices(services)
        
        // db and cache should come before api
        let dbIndex = sorted.firstIndex(where: { $0.serviceName == "db" })!
        let cacheIndex = sorted.firstIndex(where: { $0.serviceName == "cache" })!
        let apiIndex = sorted.firstIndex(where: { $0.serviceName == "api" })!
        let frontendIndex = sorted.firstIndex(where: { $0.serviceName == "frontend" })!
        
        #expect(dbIndex < apiIndex)
        #expect(cacheIndex < apiIndex)
        #expect(apiIndex < frontendIndex)
    }
}

extension DockerComposeParsingTests {
    static let dockerComposeYaml1 = """
        version: '3.8'
        
        services:
          wordpress:
            image: wordpress:latest
            ports:
              - "8080:80"
            environment:
              WORDPRESS_DB_HOST: db
              WORDPRESS_DB_USER: wordpress
              WORDPRESS_DB_PASSWORD: wordpress
              WORDPRESS_DB_NAME: wordpress
            depends_on:
              - db
            volumes:
              - wordpress_data:/var/www/html
          
          db:
            image: mysql:8.0
            environment:
              MYSQL_DATABASE: wordpress
              MYSQL_USER: wordpress
              MYSQL_PASSWORD: wordpress
              MYSQL_ROOT_PASSWORD: rootpassword
            volumes:
              - db_data:/var/lib/mysql
        
        volumes:
          wordpress_data:
          db_data:
        """
    
    static let dockerComposeYaml2 = """
        version: '3.8'
        name: webapp
        
        services:
          nginx:
            image: nginx:alpine
            ports:
              - "80:80"
            depends_on:
              - app
            networks:
              - frontend
          
          app:
            image: node:18-alpine
            working_dir: /app
            environment:
              NODE_ENV: production
              DATABASE_URL: postgres://db:5432/myapp
            depends_on:
              - db
              - redis
            networks:
              - frontend
              - backend
          
          db:
            image: postgres:14-alpine
            environment:
              POSTGRES_DB: myapp
              POSTGRES_USER: user
              POSTGRES_PASSWORD: password
            volumes:
              - db-data:/var/lib/postgresql/data
            networks:
              - backend
          
          redis:
            image: redis:alpine
            networks:
              - backend
        
        volumes:
          db-data:
        
        networks:
          frontend:
          backend:
        """
    
    static let dockerComposeYaml3 = """
        version: '3.8'
        
        services:
          api-gateway:
            image: traefik:v2.10
            ports:
              - "80:80"
              - "8080:8080"
            depends_on:
              - auth-service
              - user-service
              - order-service
          
          auth-service:
            image: auth:latest
            environment:
              JWT_SECRET: secret123
              DATABASE_URL: postgres://db:5432/auth
          
          user-service:
            image: user:latest
            environment:
              DATABASE_URL: postgres://db:5432/users
          
          order-service:
            image: order:latest
            environment:
              DATABASE_URL: postgres://db:5432/orders
          
          db:
            image: postgres:14
            environment:
              POSTGRES_PASSWORD: postgres
        """
    
    static let dockerComposeYaml4 = """
        version: '3.8'
        
        services:
          app:
            build:
              context: .
              dockerfile: Dockerfile.dev
            volumes:
              - ./app:/app
              - /app/node_modules
            environment:
              NODE_ENV: development
            ports:
              - "3000:3000"
            command: npm run dev
        """
    
    static let dockerComposeYaml5 = """
        version: '3.8'
        
        services:
          app:
            image: myapp:latest
            configs:
              - source: app_config
                target: /etc/app/config.yml
            secrets:
              - db_password
        
        configs:
          app_config:
            external: true
        
        secrets:
          db_password:
            external: true
        """
    
    static let dockerComposeYaml6 = """
        version: '3.8'
        
        services:
          web:
            image: nginx:latest
            restart: unless-stopped
            healthcheck:
              test: ["CMD", "curl", "-f", "http://localhost"]
              interval: 30s
              timeout: 10s
              retries: 3
              start_period: 40s
          
          db:
            image: postgres:14
            restart: always
            healthcheck:
              test: ["CMD-SHELL", "pg_isready -U postgres"]
              interval: 10s
              timeout: 5s
              retries: 5
        """
    
    static let dockerComposeYaml7 = """
        version: '3.8'
        
        services:
          frontend:
            image: frontend:latest
            depends_on:
              - api
          
          api:
            image: api:latest
            depends_on:
              - cache
              - db
          
          cache:
            image: redis:alpine
          
          db:
            image: postgres:14
        """
}
