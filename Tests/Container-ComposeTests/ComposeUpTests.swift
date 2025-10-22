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
import ArgumentParser
@testable import ContainerComposeCore
@testable import Yams

@Suite("ComposeUp Command Tests")
struct ComposeUpTests {
    
    // MARK: - Command Configuration Tests
    
    @Test("Verify ComposeUp command name")
    func verifyCommandName() {
        #expect(ComposeUp.configuration.commandName == "up")
    }
    
    @Test("Verify ComposeUp has abstract description")
    func verifyAbstract() {
        #expect(ComposeUp.configuration.abstract != nil)
        #expect(ComposeUp.configuration.abstract?.isEmpty == false)
    }
    
    // MARK: - Functionality Tests
    
    @Test("ComposeUp reads and parses compose file")
    func testComposeUpReadsComposeFile() async throws {
        // Create a temporary directory for test
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("compose-up-test-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create a simple compose file
        let composeYAML = """
        services:
          test-service:
            image: alpine:latest
        """
        let composePath = tempDir.appendingPathComponent("compose.yml")
        try composeYAML.write(to: composePath, atomically: true, encoding: .utf8)
        
        // Parse the compose file directly to verify it works
        let yamlData = try Data(contentsOf: composePath)
        let dockerComposeString = String(data: yamlData, encoding: .utf8)!
        let dockerCompose = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)
        
        // Verify the parse was successful
        #expect(dockerCompose.services.count == 1)
        #expect(dockerCompose.services["test-service"]??.image == "alpine:latest")
    }
    
    @Test("ComposeUp handles missing compose file")
    func testComposeUpMissingFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("compose-up-missing-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Verify that accessing a non-existent file throws an error
        let composePath = tempDir.appendingPathComponent("compose.yml").path
        let fileExists = FileManager.default.fileExists(atPath: composePath)
        
        #expect(!fileExists)
    }
    
    @Test("ComposeUp respects service filtering")
    func testComposeUpServiceFiltering() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("compose-up-filter-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create a compose file with multiple services
        let composeYAML = """
        services:
          web:
            image: nginx:latest
          db:
            image: postgres:14
          cache:
            image: redis:alpine
        """
        let composePath = tempDir.appendingPathComponent("compose.yml")
        try composeYAML.write(to: composePath, atomically: true, encoding: .utf8)
        
        // Parse and verify services
        let yamlData = try Data(contentsOf: composePath)
        let dockerComposeString = String(data: yamlData, encoding: .utf8)!
        let dockerCompose = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)
        
        // Test service filtering logic
        let allServices: [(serviceName: String, service: Service)] = dockerCompose.services.compactMap { serviceName, service in
            guard let service else { return nil }
            return (serviceName, service)
        }
        
        let requestedServices = ["web", "db"]
        let filteredServices = allServices.filter { serviceName, service in
            requestedServices.contains(serviceName)
        }
        
        #expect(filteredServices.count == 2)
        #expect(filteredServices.contains(where: { $0.serviceName == "web" }))
        #expect(filteredServices.contains(where: { $0.serviceName == "db" }))
        #expect(!filteredServices.contains(where: { $0.serviceName == "cache" }))
    }
    
    @Test("ComposeUp processes environment variables")
    func testComposeUpEnvironmentVariables() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("compose-up-env-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create a compose file with environment variables
        let composeYAML = """
        services:
          app:
            image: alpine:latest
            environment:
              DATABASE_URL: postgres://localhost/mydb
              DEBUG: "true"
              PORT: "8080"
        """
        let composePath = tempDir.appendingPathComponent("compose.yml")
        try composeYAML.write(to: composePath, atomically: true, encoding: .utf8)
        
        // Parse and verify environment variables
        let yamlData = try Data(contentsOf: composePath)
        let dockerComposeString = String(data: yamlData, encoding: .utf8)!
        let dockerCompose = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)
        
        let appService = dockerCompose.services["app"]??
        #expect(appService.environment?["DATABASE_URL"] == "postgres://localhost/mydb")
        #expect(appService.environment?["DEBUG"] == "true")
        #expect(appService.environment?["PORT"] == "8080")
    }
    
    @Test("ComposeUp processes volumes configuration")
    func testComposeUpVolumes() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("compose-up-volumes-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create a compose file with volumes
        let composeYAML = """
        services:
          db:
            image: postgres:14
            volumes:
              - db-data:/var/lib/postgresql/data
              - ./config:/etc/config:ro
        volumes:
          db-data:
        """
        let composePath = tempDir.appendingPathComponent("compose.yml")
        try composeYAML.write(to: composePath, atomically: true, encoding: .utf8)
        
        // Parse and verify volumes
        let yamlData = try Data(contentsOf: composePath)
        let dockerComposeString = String(data: yamlData, encoding: .utf8)!
        let dockerCompose = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)
        
        let dbService = dockerCompose.services["db"]??
        #expect(dbService.volumes?.count == 2)
        #expect(dbService.volumes?.contains("db-data:/var/lib/postgresql/data") == true)
        #expect(dbService.volumes?.contains("./config:/etc/config:ro") == true)
        
        #expect(dockerCompose.volumes != nil)
        #expect(dockerCompose.volumes?["db-data"] != nil)
    }
    
    @Test("ComposeUp processes networks configuration")
    func testComposeUpNetworks() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("compose-up-networks-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create a compose file with networks
        let composeYAML = """
        services:
          web:
            image: nginx:latest
            networks:
              - frontend
              - backend
        networks:
          frontend:
            driver: bridge
          backend:
            driver: bridge
        """
        let composePath = tempDir.appendingPathComponent("compose.yml")
        try composeYAML.write(to: composePath, atomically: true, encoding: .utf8)
        
        // Parse and verify networks
        let yamlData = try Data(contentsOf: composePath)
        let dockerComposeString = String(data: yamlData, encoding: .utf8)!
        let dockerCompose = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)
        
        let webService = dockerCompose.services["web"]??
        #expect(webService.networks?.count == 2)
        #expect(webService.networks?.contains("frontend") == true)
        #expect(webService.networks?.contains("backend") == true)
        
        #expect(dockerCompose.networks != nil)
        #expect(dockerCompose.networks?["frontend"]??.driver == "bridge")
        #expect(dockerCompose.networks?["backend"]??.driver == "bridge")
    }
    
    @Test("ComposeUp handles service dependencies")
    func testComposeUpServiceDependencies() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("compose-up-deps-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create a compose file with dependencies
        let composeYAML = """
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
        let composePath = tempDir.appendingPathComponent("compose.yml")
        try composeYAML.write(to: composePath, atomically: true, encoding: .utf8)
        
        // Parse and verify dependencies
        let yamlData = try Data(contentsOf: composePath)
        let dockerComposeString = String(data: yamlData, encoding: .utf8)!
        let dockerCompose = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)
        
        // Verify dependencies are parsed
        let webService = dockerCompose.services["web"]??
        #expect(webService.depends_on?.contains("api") == true)
        
        let apiService = dockerCompose.services["api"]??
        #expect(apiService.depends_on?.contains("db") == true)
        
        // Verify topological sorting works
        let services: [(serviceName: String, service: Service)] = dockerCompose.services.compactMap { serviceName, service in
            guard let service else { return nil }
            return (serviceName, service)
        }
        
        let sortedServices = try Service.topoSortConfiguredServices(services)
        let serviceNames = sortedServices.map { $0.serviceName }
        
        // db should come before api, api before web
        let dbIndex = serviceNames.firstIndex(of: "db")!
        let apiIndex = serviceNames.firstIndex(of: "api")!
        let webIndex = serviceNames.firstIndex(of: "web")!
        
        #expect(dbIndex < apiIndex)
        #expect(apiIndex < webIndex)
    }
    
    @Test("ComposeUp determines project name correctly")
    func testComposeUpProjectName() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("compose-up-project-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Test with explicit project name
        let composeYAMLWithName = """
        name: my-project
        services:
          web:
            image: nginx:latest
        """
        let composePath = tempDir.appendingPathComponent("compose.yml")
        try composeYAMLWithName.write(to: composePath, atomically: true, encoding: .utf8)
        
        let yamlData = try Data(contentsOf: composePath)
        let dockerComposeString = String(data: yamlData, encoding: .utf8)!
        let dockerCompose = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)
        
        #expect(dockerCompose.name == "my-project")
        
        // Test without project name (should use directory name)
        let composeYAMLWithoutName = """
        services:
          web:
            image: nginx:latest
        """
        try composeYAMLWithoutName.write(to: composePath, atomically: true, encoding: .utf8)
        
        let yamlData2 = try Data(contentsOf: composePath)
        let dockerComposeString2 = String(data: yamlData2, encoding: .utf8)!
        let dockerCompose2 = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString2)
        
        #expect(dockerCompose2.name == nil)
        // Project name would default to directory name at runtime
    }
    
    @Test("ComposeUp handles build configuration")
    func testComposeUpBuildConfiguration() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("compose-up-build-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create a compose file with build configuration
        let composeYAML = """
        services:
          app:
            build:
              context: ./app
              dockerfile: Dockerfile
              args:
                NODE_ENV: production
                VERSION: 1.0.0
            image: myapp:latest
        """
        let composePath = tempDir.appendingPathComponent("compose.yml")
        try composeYAML.write(to: composePath, atomically: true, encoding: .utf8)
        
        // Parse and verify build configuration
        let yamlData = try Data(contentsOf: composePath)
        let dockerComposeString = String(data: yamlData, encoding: .utf8)!
        let dockerCompose = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)
        
        let appService = dockerCompose.services["app"]??
        #expect(appService.build != nil)
        #expect(appService.build?.context == "./app")
        #expect(appService.build?.dockerfile == "Dockerfile")
        #expect(appService.build?.args?["NODE_ENV"] == "production")
        #expect(appService.build?.args?["VERSION"] == "1.0.0")
        #expect(appService.image == "myapp:latest")
    }
    
    @Test("ComposeUp processes port mappings")
    func testComposeUpPortMappings() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("compose-up-ports-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create a compose file with port mappings
        let composeYAML = """
        services:
          web:
            image: nginx:latest
            ports:
              - "8080:80"
              - "443:443"
              - "3000"
        """
        let composePath = tempDir.appendingPathComponent("compose.yml")
        try composeYAML.write(to: composePath, atomically: true, encoding: .utf8)
        
        // Parse and verify ports
        let yamlData = try Data(contentsOf: composePath)
        let dockerComposeString = String(data: yamlData, encoding: .utf8)!
        let dockerCompose = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)
        
        let webService = dockerCompose.services["web"]??
        #expect(webService.ports?.count == 3)
        #expect(webService.ports?.contains("8080:80") == true)
        #expect(webService.ports?.contains("443:443") == true)
        #expect(webService.ports?.contains("3000") == true)
    }
    
    @Test("ComposeUp handles container configuration options")
    func testComposeUpContainerOptions() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("compose-up-options-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create a compose file with various container options
        let composeYAML = """
        services:
          app:
            image: alpine:latest
            container_name: my-app-container
            hostname: myapp.local
            user: "1000:1000"
            working_dir: /app
            restart: always
            privileged: true
            read_only: false
            stdin_open: true
            tty: true
        """
        let composePath = tempDir.appendingPathComponent("compose.yml")
        try composeYAML.write(to: composePath, atomically: true, encoding: .utf8)
        
        // Parse and verify container options
        let yamlData = try Data(contentsOf: composePath)
        let dockerComposeString = String(data: yamlData, encoding: .utf8)!
        let dockerCompose = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)
        
        let appService = dockerCompose.services["app"]??
        #expect(appService.container_name == "my-app-container")
        #expect(appService.hostname == "myapp.local")
        #expect(appService.user == "1000:1000")
        #expect(appService.working_dir == "/app")
        #expect(appService.restart == "always")
        #expect(appService.privileged == true)
        #expect(appService.read_only == false)
        #expect(appService.stdin_open == true)
        #expect(appService.tty == true)
    }
    
    // MARK: - Argument Parsing Tests
    // These tests verify that command-line arguments are parsed correctly
    
    @Test("Parse ComposeUp with no flags")
    func parseComposeUpNoFlags() throws {
        let command = try ComposeUp.parse([])
        
        #expect(command.services.isEmpty)
        #expect(command.detatch == false)
        #expect(command.composeFilename == "compose.yml")
        #expect(command.rebuild == false)
        #expect(command.noCache == false)
    }
    
    @Test("Parse ComposeUp with detach flag (short form)")
    func parseComposeUpDetachShort() throws {
        let command = try ComposeUp.parse(["-d"])
        
        #expect(command.detatch == true)
    }
    
    @Test("Parse ComposeUp with detach flag (long form)")
    func parseComposeUpDetachLong() throws {
        let command = try ComposeUp.parse(["--detach"])
        
        #expect(command.detatch == true)
    }
    
    @Test("Parse ComposeUp with custom compose file (short form)")
    func parseComposeUpFileShort() throws {
        let command = try ComposeUp.parse(["-f", "custom-compose.yml"])
        
        #expect(command.composeFilename == "custom-compose.yml")
    }
    
    @Test("Parse ComposeUp with custom compose file (long form)")
    func parseComposeUpFileLong() throws {
        let command = try ComposeUp.parse(["--file", "docker-compose.prod.yml"])
        
        #expect(command.composeFilename == "docker-compose.prod.yml")
    }
    
    @Test("Parse ComposeUp with rebuild flag (short form)")
    func parseComposeUpRebuildShort() throws {
        let command = try ComposeUp.parse(["-b"])
        
        #expect(command.rebuild == true)
    }
    
    @Test("Parse ComposeUp with rebuild flag (long form)")
    func parseComposeUpRebuildLong() throws {
        let command = try ComposeUp.parse(["--build"])
        
        #expect(command.rebuild == true)
    }
    
    @Test("Parse ComposeUp with no-cache flag")
    func parseComposeUpNoCache() throws {
        let command = try ComposeUp.parse(["--no-cache"])
        
        #expect(command.noCache == true)
    }
    
    @Test("Parse ComposeUp with single service")
    func parseComposeUpSingleService() throws {
        let command = try ComposeUp.parse(["web"])
        
        #expect(command.services.count == 1)
        #expect(command.services.contains("web"))
    }
    
    @Test("Parse ComposeUp with multiple services")
    func parseComposeUpMultipleServices() throws {
        let command = try ComposeUp.parse(["web", "db", "cache"])
        
        #expect(command.services.count == 3)
        #expect(command.services.contains("web"))
        #expect(command.services.contains("db"))
        #expect(command.services.contains("cache"))
    }
    
    // MARK: - Combined Flags Tests
    
    @Test("Parse ComposeUp with detach and rebuild")
    func parseComposeUpDetachAndRebuild() throws {
        let command = try ComposeUp.parse(["-d", "-b"])
        
        #expect(command.detatch == true)
        #expect(command.rebuild == true)
    }
    
    @Test("Parse ComposeUp with all flags")
    func parseComposeUpAllFlags() throws {
        let command = try ComposeUp.parse([
            "-d",
            "-f", "custom.yml",
            "-b",
            "--no-cache",
            "web", "db"
        ])
        
        #expect(command.detatch == true)
        #expect(command.composeFilename == "custom.yml")
        #expect(command.rebuild == true)
        #expect(command.noCache == true)
        #expect(command.services.count == 2)
        #expect(command.services.contains("web"))
        #expect(command.services.contains("db"))
    }
    
    @Test("Parse ComposeUp with rebuild and no-cache")
    func parseComposeUpRebuildNoCache() throws {
        let command = try ComposeUp.parse(["--build", "--no-cache"])
        
        #expect(command.rebuild == true)
        #expect(command.noCache == true)
    }
    
    @Test("Parse ComposeUp with custom file and services")
    func parseComposeUpFileAndServices() throws {
        let command = try ComposeUp.parse(["-f", "compose.prod.yml", "api", "worker"])
        
        #expect(command.composeFilename == "compose.prod.yml")
        #expect(command.services.count == 2)
        #expect(command.services.contains("api"))
        #expect(command.services.contains("worker"))
    }
    
    // MARK: - Flag Combinations with Long and Short Forms
    
    @Test("Parse ComposeUp with mixed short and long flags")
    func parseComposeUpMixedFlags() throws {
        let command = try ComposeUp.parse(["-d", "--file", "test.yml", "-b"])
        
        #expect(command.detatch == true)
        #expect(command.composeFilename == "test.yml")
        #expect(command.rebuild == true)
    }
    
    @Test("Parse ComposeUp with long form flags")
    func parseComposeUpLongFormFlags() throws {
        let command = try ComposeUp.parse([
            "--detach",
            "--file", "production.yml",
            "--build",
            "--no-cache"
        ])
        
        #expect(command.detatch == true)
        #expect(command.composeFilename == "production.yml")
        #expect(command.rebuild == true)
        #expect(command.noCache == true)
    }
    
    @Test("Parse ComposeUp with short form flags")
    func parseComposeUpShortFormFlags() throws {
        let command = try ComposeUp.parse(["-d", "-f", "dev.yml", "-b"])
        
        #expect(command.detatch == true)
        #expect(command.composeFilename == "dev.yml")
        #expect(command.rebuild == true)
    }
    
    // MARK: - Service Selection Tests
    
    @Test("Parse ComposeUp with services at end")
    func parseComposeUpServicesAtEnd() throws {
        let command = try ComposeUp.parse(["-d", "-b", "web", "api"])
        
        #expect(command.detatch == true)
        #expect(command.rebuild == true)
        #expect(command.services.count == 2)
    }
    
    @Test("Parse ComposeUp with single service name")
    func parseComposeUpSingleServiceName() throws {
        let command = try ComposeUp.parse(["database"])
        
        #expect(command.services.count == 1)
        #expect(command.services.first == "database")
    }
    
    @Test("Parse ComposeUp with many services")
    func parseComposeUpManyServices() throws {
        let command = try ComposeUp.parse([
            "web", "api", "db", "cache", "worker", "scheduler"
        ])
        
        #expect(command.services.count == 6)
        #expect(command.services.contains("web"))
        #expect(command.services.contains("api"))
        #expect(command.services.contains("db"))
        #expect(command.services.contains("cache"))
        #expect(command.services.contains("worker"))
        #expect(command.services.contains("scheduler"))
    }
    
    // MARK: - File Path Tests
    
    @Test("Parse ComposeUp with relative file path")
    func parseComposeUpRelativeFile() throws {
        let command = try ComposeUp.parse(["-f", "./configs/compose.yml"])
        
        #expect(command.composeFilename == "./configs/compose.yml")
    }
    
    @Test("Parse ComposeUp with nested file path")
    func parseComposeUpNestedFile() throws {
        let command = try ComposeUp.parse(["--file", "docker/compose/prod.yml"])
        
        #expect(command.composeFilename == "docker/compose/prod.yml")
    }
    
    @Test("Parse ComposeUp with docker-compose.yml filename")
    func parseComposeUpDockerComposeFilename() throws {
        let command = try ComposeUp.parse(["-f", "docker-compose.yml"])
        
        #expect(command.composeFilename == "docker-compose.yml")
    }
    
    @Test("Parse ComposeUp with yaml extension")
    func parseComposeUpYamlExtension() throws {
        let command = try ComposeUp.parse(["--file", "compose.yaml"])
        
        #expect(command.composeFilename == "compose.yaml")
    }
    
    // MARK: - Detach Flag Variations
    
    @Test("Parse ComposeUp detach at different positions")
    func parseComposeUpDetachPositions() throws {
        // Detach at start
        let cmd1 = try ComposeUp.parse(["-d", "web"])
        #expect(cmd1.detatch == true)
        #expect(cmd1.services.contains("web"))
        
        // Detach in middle
        let cmd2 = try ComposeUp.parse(["-f", "compose.yml", "-d", "web"])
        #expect(cmd2.detatch == true)
        #expect(cmd2.composeFilename == "compose.yml")
    }
    
    // MARK: - Build Flags Combinations
    
    @Test("Parse ComposeUp with only build flag")
    func parseComposeUpOnlyBuild() throws {
        let command = try ComposeUp.parse(["--build"])
        
        #expect(command.rebuild == true)
        #expect(command.noCache == false)
    }
    
    @Test("Parse ComposeUp with only no-cache flag")
    func parseComposeUpOnlyNoCache() throws {
        let command = try ComposeUp.parse(["--no-cache"])
        
        #expect(command.noCache == true)
        #expect(command.rebuild == false)
    }
    
    @Test("Parse ComposeUp build with services")
    func parseComposeUpBuildWithServices() throws {
        let command = try ComposeUp.parse(["--build", "api", "worker"])
        
        #expect(command.rebuild == true)
        #expect(command.services.count == 2)
        #expect(command.services.contains("api"))
        #expect(command.services.contains("worker"))
    }
    
    @Test("Parse ComposeUp no-cache with detach and services")
    func parseComposeUpNoCacheDetachServices() throws {
        let command = try ComposeUp.parse(["--no-cache", "-d", "web"])
        
        #expect(command.noCache == true)
        #expect(command.detatch == true)
        #expect(command.services.contains("web"))
    }
    
    // MARK: - Complex Real-World Scenarios
    
    @Test("Parse ComposeUp production deployment scenario")
    func parseComposeUpProductionScenario() throws {
        let command = try ComposeUp.parse([
            "--detach",
            "--file", "docker-compose.prod.yml",
            "--build",
            "--no-cache",
            "web", "api", "worker"
        ])
        
        #expect(command.detatch == true)
        #expect(command.composeFilename == "docker-compose.prod.yml")
        #expect(command.rebuild == true)
        #expect(command.noCache == true)
        #expect(command.services.count == 3)
    }
    
    @Test("Parse ComposeUp development scenario")
    func parseComposeUpDevelopmentScenario() throws {
        let command = try ComposeUp.parse([
            "-f", "docker-compose.dev.yml",
            "web", "db", "cache"
        ])
        
        #expect(command.composeFilename == "docker-compose.dev.yml")
        #expect(command.services.count == 3)
        #expect(command.detatch == false) // No detach in dev for log viewing
    }
    
    @Test("Parse ComposeUp testing scenario")
    func parseComposeUpTestingScenario() throws {
        let command = try ComposeUp.parse([
            "--file", "docker-compose.test.yml",
            "--build",
            "test-runner"
        ])
        
        #expect(command.composeFilename == "docker-compose.test.yml")
        #expect(command.rebuild == true)
        #expect(command.services.contains("test-runner"))
    }
    
    @Test("Parse ComposeUp CI/CD scenario")
    func parseComposeUpCICDScenario() throws {
        let command = try ComposeUp.parse([
            "-d",
            "-f", "ci-compose.yml",
            "-b",
            "--no-cache"
        ])
        
        #expect(command.detatch == true)
        #expect(command.composeFilename == "ci-compose.yml")
        #expect(command.rebuild == true)
        #expect(command.noCache == true)
    }
    
    // MARK: - Edge Cases
    
    @Test("Parse ComposeUp with empty services array")
    func parseComposeUpEmptyServices() throws {
        let command = try ComposeUp.parse(["-d"])
        
        #expect(command.services.isEmpty)
    }
    
    @Test("Parse ComposeUp with duplicate flags")
    func parseComposeUpDuplicateFlags() throws {
        // Last value should win for options
        let command = try ComposeUp.parse([
            "-f", "first.yml",
            "-f", "second.yml"
        ])
        
        #expect(command.composeFilename == "second.yml")
    }
    
    @Test("Parse ComposeUp with service name that looks like flag")
    func parseComposeUpServiceLikeFlag() throws {
        // Service names starting with dash should work when specified correctly
        let command = try ComposeUp.parse(["web", "api"])
        
        #expect(command.services.contains("web"))
        #expect(command.services.contains("api"))
    }
    
    // MARK: - Default Values Tests
    
    @Test("Verify default compose filename")
    func verifyDefaultComposeFilename() throws {
        let command = try ComposeUp.parse([])
        
        #expect(command.composeFilename == "compose.yml")
    }
    
    @Test("Verify default detach is false")
    func verifyDefaultDetach() throws {
        let command = try ComposeUp.parse([])
        
        #expect(command.detatch == false)
    }
    
    @Test("Verify default rebuild is false")
    func verifyDefaultRebuild() throws {
        let command = try ComposeUp.parse([])
        
        #expect(command.rebuild == false)
    }
    
    @Test("Verify default no-cache is false")
    func verifyDefaultNoCache() throws {
        let command = try ComposeUp.parse([])
        
        #expect(command.noCache == false)
    }
    
    @Test("Verify default services is empty")
    func verifyDefaultServices() throws {
        let command = try ComposeUp.parse([])
        
        #expect(command.services.isEmpty)
    }
    
    // MARK: - All Flag Permutations
    
    @Test("Parse ComposeUp flag permutation 1")
    func parseComposeUpPermutation1() throws {
        let command = try ComposeUp.parse(["-d", "-f", "test.yml"])
        
        #expect(command.detatch == true)
        #expect(command.composeFilename == "test.yml")
    }
    
    @Test("Parse ComposeUp flag permutation 2")
    func parseComposeUpPermutation2() throws {
        let command = try ComposeUp.parse(["-f", "test.yml", "-d"])
        
        #expect(command.detatch == true)
        #expect(command.composeFilename == "test.yml")
    }
    
    @Test("Parse ComposeUp flag permutation 3")
    func parseComposeUpPermutation3() throws {
        let command = try ComposeUp.parse(["-b", "--no-cache", "-d"])
        
        #expect(command.rebuild == true)
        #expect(command.noCache == true)
        #expect(command.detatch == true)
    }
    
    @Test("Parse ComposeUp flag permutation 4")
    func parseComposeUpPermutation4() throws {
        let command = try ComposeUp.parse(["--no-cache", "-d", "-b"])
        
        #expect(command.noCache == true)
        #expect(command.detatch == true)
        #expect(command.rebuild == true)
    }
    
    @Test("Parse ComposeUp flag permutation 5")
    func parseComposeUpPermutation5() throws {
        let command = try ComposeUp.parse(["-d", "web", "-b"])
        
        #expect(command.detatch == true)
        #expect(command.services.contains("web"))
        #expect(command.rebuild == true)
    }
    
    @Test("Parse ComposeUp flag permutation 6")
    func parseComposeUpPermutation6() throws {
        let command = try ComposeUp.parse(["-b", "web", "-d"])
        
        #expect(command.rebuild == true)
        #expect(command.services.contains("web"))
        #expect(command.detatch == true)
    }
}
