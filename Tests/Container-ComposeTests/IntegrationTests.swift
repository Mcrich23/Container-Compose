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

@Suite("Integration Tests - Real-World Compose Files")
struct IntegrationTests {
    
    @Test("Parse WordPress with MySQL compose file")
    func parseWordPressCompose() throws {
        let yaml = """
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
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(FullDockerCompose.self, from: yaml)
        
        #expect(compose.services.count == 2)
        #expect(compose.services["wordpress"] != nil)
        #expect(compose.services["db"] != nil)
        #expect(compose.volumes?.count == 2)
        #expect(compose.services["wordpress"]?.depends_on?.contains("db") == true)
    }
    
    @Test("Parse three-tier web application")
    func parseThreeTierApp() throws {
        let yaml = """
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
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(FullDockerCompose.self, from: yaml)
        
        #expect(compose.name == "webapp")
        #expect(compose.services.count == 4)
        #expect(compose.networks?.count == 2)
        #expect(compose.volumes?.count == 1)
    }
    
    @Test("Parse microservices architecture")
    func parseMicroservicesCompose() throws {
        let yaml = """
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
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(FullDockerCompose.self, from: yaml)
        
        #expect(compose.services.count == 5)
        #expect(compose.services["api-gateway"]?.depends_on?.count == 3)
    }
    
    @Test("Parse development environment with build")
    func parseDevelopmentEnvironment() throws {
        let yaml = """
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
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(FullDockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]?.build != nil)
        #expect(compose.services["app"]?.build?.context == ".")
        #expect(compose.services["app"]?.volumes?.count == 2)
    }
    
    @Test("Parse compose with secrets and configs")
    func parseComposeWithSecretsAndConfigs() throws {
        let yaml = """
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
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(FullDockerCompose.self, from: yaml)
        
        #expect(compose.configs != nil)
        #expect(compose.secrets != nil)
    }
    
    @Test("Parse compose with healthchecks and restart policies")
    func parseComposeWithHealthchecksAndRestart() throws {
        let yaml = """
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
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(FullDockerCompose.self, from: yaml)
        
        #expect(compose.services["web"]?.restart == "unless-stopped")
        #expect(compose.services["web"]?.healthcheck != nil)
        #expect(compose.services["db"]?.restart == "always")
    }
    
    @Test("Parse compose with complex dependency chain")
    func parseComplexDependencyChain() throws {
        let yaml = """
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
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(FullDockerCompose.self, from: yaml)
        
        #expect(compose.services.count == 4)
        
        // Test dependency resolution
        let services: [(String, TestService)] = compose.services.map { ($0, $1) }
        let sorted = try TestService.topoSortConfiguredServices(services)
        
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

// Test helper structs
struct FullDockerCompose: Codable {
    let version: String?
    let name: String?
    let services: [String: TestService]
    let volumes: [String: Volume]?
    let networks: [String: Network]?
    let configs: [String: Config]?
    let secrets: [String: Secret]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        services = try container.decode([String: TestService].self, forKey: .services)
        
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
    
    enum CodingKeys: String, CodingKey {
        case version, name, services, volumes, networks, configs, secrets
    }
}

struct TestService: Codable, Hashable {
    let image: String?
    let build: Build?
    let restart: String?
    let healthcheck: Healthcheck?
    let volumes: [String]?
    let environment: [String: String]?
    let ports: [String]?
    let command: String?
    let depends_on: [String]?
    let working_dir: String?
    let networks: [String]?
    let configs: [ServiceConfig]?
    let secrets: [ServiceSecret]?
    var dependedBy: [String] = []
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        build = try container.decodeIfPresent(Build.self, forKey: .build)
        restart = try container.decodeIfPresent(String.self, forKey: .restart)
        healthcheck = try container.decodeIfPresent(Healthcheck.self, forKey: .healthcheck)
        volumes = try container.decodeIfPresent([String].self, forKey: .volumes)
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment)
        ports = try container.decodeIfPresent([String].self, forKey: .ports)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        depends_on = try container.decodeIfPresent([String].self, forKey: .depends_on)
        working_dir = try container.decodeIfPresent(String.self, forKey: .working_dir)
        networks = try container.decodeIfPresent([String].self, forKey: .networks)
        configs = try container.decodeIfPresent([ServiceConfig].self, forKey: .configs)
        secrets = try container.decodeIfPresent([ServiceSecret].self, forKey: .secrets)
    }
    
    enum CodingKeys: String, CodingKey {
        case image, build, restart, healthcheck, volumes, environment, ports, command, depends_on, working_dir, networks, configs, secrets
    }
    
    static func topoSortConfiguredServices(
        _ services: [(serviceName: String, service: TestService)]
    ) throws -> [(serviceName: String, service: TestService)] {
        
        var visited = Set<String>()
        var visiting = Set<String>()
        var sorted: [(String, TestService)] = []
        
        func visit(_ name: String, from service: String? = nil) throws {
            guard var serviceTuple = services.first(where: { $0.serviceName == name }) else { return }
            if let service {
                serviceTuple.service.dependedBy.append(service)
            }
            
            if visiting.contains(name) {
                throw NSError(domain: "ComposeError", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Cyclic dependency detected involving '\(name)'"
                ])
            }
            guard !visited.contains(name) else { return }
            
            visiting.insert(name)
            for depName in serviceTuple.service.depends_on ?? [] {
                try visit(depName, from: name)
            }
            visiting.remove(name)
            visited.insert(name)
            sorted.append(serviceTuple)
        }
        
        for (serviceName, _) in services {
            if !visited.contains(serviceName) {
                try visit(serviceName)
            }
        }
        
        return sorted
    }
}
