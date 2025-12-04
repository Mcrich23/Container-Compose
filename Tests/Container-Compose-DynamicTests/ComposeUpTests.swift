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
import ContainerClient
import TestHelpers
@testable import ContainerComposeCore

@Suite("Compose Up Tests - Real-World Compose Files", .containerDependent, .serialized)
struct ComposeUpTests {
    
    @Test("Test WordPress with MySQL compose file")
    func testWordPressCompose() async throws {
        let yaml = DockerComposeYamlFiles.dockerComposeYaml1
        
        let tempLocation = URL.temporaryDirectory.appending(path: "Container-Compose_Tests_\(UUID().uuidString)/docker-compose.yaml")
        try? FileManager.default.createDirectory(at: tempLocation.deletingLastPathComponent(), withIntermediateDirectories: true)
        try yaml.write(to: tempLocation, atomically: false, encoding: .utf8)
        let folderName = tempLocation.deletingLastPathComponent().lastPathComponent
        
        var composeUp = try ComposeUp.parse(["-d", "--cwd", tempLocation.deletingLastPathComponent().path(percentEncoded: false)])
        try await composeUp.run()
        
        // Get these containers
        let containers = try await ClientContainer.list()
            .filter({
                $0.configuration.id.contains(tempLocation.deletingLastPathComponent().lastPathComponent)
            })
        
        // Assert correct wordpress container information
        guard let wordpressContainer = containers.first(where: { $0.configuration.id == "\(folderName)-wordpress" }),
              let dbContainer = containers.first(where: { $0.configuration.id == "\(folderName)-db" })
        else {
            throw Errors.containerNotFound
        }
        
        // Check Ports
        #expect(wordpressContainer.configuration.publishedPorts.map({ "\($0.hostAddress):\($0.hostPort):\($0.containerPort)" }) == ["0.0.0.0:8080:80"])
        
        // Check Image
        #expect(wordpressContainer.configuration.image.reference == "docker.io/library/wordpress:latest")
        
        // Check Environment
        let wpEnv = parseEnvToDict(wordpressContainer.configuration.initProcess.environment)
        #expect(wpEnv["WORDPRESS_DB_HOST"] == String(dbContainer.networks.first!.address.split(separator: "/")[0]))
        #expect(wpEnv["WORDPRESS_DB_USER"] == "wordpress")
        #expect(wpEnv["WORDPRESS_DB_PASSWORD"] == "wordpress")
        #expect(wpEnv["WORDPRESS_DB_NAME"] == "wordpress")
        
        // Check Volume
        #expect(wordpressContainer.configuration.mounts.map(\.destination) == ["/var/www/"])
        
        // Assert correct db container information
        
        // Check Image
        #expect(dbContainer.configuration.image.reference == "docker.io/library/mysql:8.0")
        
        // Check Environment
        let dbEnv = parseEnvToDict(dbContainer.configuration.initProcess.environment)
        #expect(dbEnv["MYSQL_ROOT_PASSWORD"] == "rootpassword")
        #expect(dbEnv["MYSQL_DATABASE"] == "wordpress")
        #expect(dbEnv["MYSQL_USER"] == "wordpress")
        #expect(dbEnv["MYSQL_PASSWORD"] == "wordpress")
        
        // Check Volume
        #expect(dbContainer.configuration.mounts.map(\.destination) == ["/var/lib/"])
        print("")
    }
    
    // TODO: Reenable
//    @Test("Test three-tier web application with multiple networks")
//    func testThreeTierWebAppWithNetworks() async throws {
//        let yaml = DockerComposeYamlFiles.dockerComposeYaml2
//        
//        let tempLocation = URL.temporaryDirectory.appending(path: "Container-Compose_Tests_\(UUID().uuidString)/docker-compose.yaml")
//        try? FileManager.default.createDirectory(at: tempLocation.deletingLastPathComponent(), withIntermediateDirectories: true)
//        try yaml.write(to: tempLocation, atomically: false, encoding: .utf8)
//        let folderName = tempLocation.deletingLastPathComponent().lastPathComponent
//        
//        var composeUp = try ComposeUp.parse(["-d", "--cwd", tempLocation.deletingLastPathComponent().path(percentEncoded: false)])
//        try await composeUp.run()
//        
//        // Get the containers created by this compose file
//        let containers = try await ClientContainer.list()
//            .filter({
//                $0.configuration.id.contains(folderName)
//            })
//        
//        guard let nginxContainer = containers.first(where: { $0.configuration.id == "\(folderName)-nginx" }),
//              let appContainer = containers.first(where: { $0.configuration.id == "\(folderName)-app" }),
//              let dbContainer = containers.first(where: { $0.configuration.id == "\(folderName)-db" }),
//              let redisContainer = containers.first(where: { $0.configuration.id == "\(folderName)-redis" })
//        else {
//            throw Errors.containerNotFound
//        }
//        
//        // --- NGINX Container ---
//        #expect(nginxContainer.configuration.image.reference == "docker.io/library/nginx:alpine")
//        #expect(nginxContainer.configuration.publishedPorts.map({ "\($0.hostAddress):\($0.hostPort):\($0.containerPort)" }) == ["0.0.0.0:80:80"])
//        #expect(nginxContainer.networks.map(\.hostname).contains("frontend"))
//        
//        // --- APP Container ---
//        #expect(appContainer.configuration.image.reference == "docker.io/library/node:18-alpine")
//        
//        let appEnv = parseEnvToDict(appContainer.configuration.initProcess.environment)
//        #expect(appEnv["NODE_ENV"] == "production")
//        #expect(appEnv["DATABASE_URL"] == "postgres://\(dbContainer.networks.first!.address.split(separator: "/")[0]):5432/myapp")
//        
//        #expect(appContainer.networks.map(\.hostname).sorted() == ["backend", "frontend"])
//        
//        // --- DB Container ---
//        #expect(dbContainer.configuration.image.reference == "docker.io/library/postgres:14-alpine")
//        let dbEnv = parseEnvToDict(dbContainer.configuration.initProcess.environment)
//        #expect(dbEnv["POSTGRES_DB"] == "myapp")
//        #expect(dbEnv["POSTGRES_USER"] == "user")
//        #expect(dbEnv["POSTGRES_PASSWORD"] == "password")
//        
//        // Verify volume mount
//        #expect(dbContainer.configuration.mounts.map(\.destination) == ["/var/lib/postgresql/"])
//        #expect(dbContainer.networks.map(\.hostname) == ["backend"])
//        
//        // --- Redis Container ---
//        #expect(redisContainer.configuration.image.reference == "docker.io/library/redis:alpine")
//        #expect(redisContainer.networks.map(\.hostname) == ["backend"])
//    }
    
//    @Test("Parse development environment with build")
//    func parseDevelopmentEnvironment() throws {
//        let yaml = DockerComposeYamlFiles.dockerComposeYaml4
//        
//        let decoder = YAMLDecoder()
//        let compose = try decoder.decode(DockerCompose.self, from: yaml)
//        
//        #expect(compose.services["app"]??.build != nil)
//        #expect(compose.services["app"]??.build?.context == ".")
//        #expect(compose.services["app"]??.volumes?.count == 2)
//    }
    
//    @Test("Parse compose with secrets and configs")
//    func parseComposeWithSecretsAndConfigs() throws {
//        let yaml = DockerComposeYamlFiles.dockerComposeYaml5
//        
//        let decoder = YAMLDecoder()
//        let compose = try decoder.decode(DockerCompose.self, from: yaml)
//        
//        #expect(compose.configs != nil)
//        #expect(compose.secrets != nil)
//    }
    
//    @Test("Parse compose with healthchecks and restart policies")
//    func parseComposeWithHealthchecksAndRestart() async throws {
//        let yaml = DockerComposeYamlFiles.dockerComposeYaml6
//        
//        let tempLocation = URL.temporaryDirectory.appending(path: "Container-Compose_Tests_\(UUID().uuidString)/docker-compose.yaml")
//        try? FileManager.default.createDirectory(at: tempLocation.deletingLastPathComponent(), withIntermediateDirectories: true)
//        try yaml.write(to: tempLocation, atomically: false, encoding: .utf8)
//        let folderName = tempLocation.deletingLastPathComponent().lastPathComponent
//        
//        var composeUp = try ComposeUp.parse(["-d", "--cwd", tempLocation.deletingLastPathComponent().path(percentEncoded: false)])
//        try await composeUp.run()
//        
//        // Get the containers created by this compose file
//        let containers = try await ClientContainer.list()
//            .filter({
//                $0.configuration.id.contains(folderName)
//            })
//        dump(containers)
//    }
    
    @Test("Test compose with complex dependency chain")
    func TestComplexDependencyChain() async throws {
        let yaml = DockerComposeYamlFiles.dockerComposeYaml8
        
        let tempLocation = URL.temporaryDirectory.appending(path: "Container-Compose_Tests_\(UUID().uuidString)/docker-compose.yaml")
        try? FileManager.default.createDirectory(at: tempLocation.deletingLastPathComponent(), withIntermediateDirectories: true)
        try yaml.write(to: tempLocation, atomically: false, encoding: .utf8)
        let folderName = tempLocation.deletingLastPathComponent().lastPathComponent
        
        var composeUp = try ComposeUp.parse(["-d", "--cwd", tempLocation.deletingLastPathComponent().path(percentEncoded: false)])
        try await composeUp.run()
        
        // Get the containers created by this compose file
        let containers = try await ClientContainer.list()
            .filter {
                $0.configuration.id.contains(folderName)
            }
        
        guard let webContainer = containers.first(where: { $0.configuration.id == "\(folderName)-web" }),
              let appContainer = containers.first(where: { $0.configuration.id == "\(folderName)-app" }),
              let dbContainer = containers.first(where: { $0.configuration.id == "\(folderName)-db" })
        else {
            throw Errors.containerNotFound
        }
        
        // --- WEB Container ---
        #expect(webContainer.configuration.image.reference == "docker.io/library/nginx:alpine")
        #expect(webContainer.configuration.publishedPorts.map { "\($0.hostAddress):\($0.hostPort):\($0.containerPort)" } == ["0.0.0.0:8082:80"])
        
        // --- APP Container ---
        #expect(appContainer.configuration.image.reference == "docker.io/library/python:3.12-alpine")
        let appEnv = parseEnvToDict(appContainer.configuration.initProcess.environment)
        #expect(appEnv["DATABASE_URL"] == "postgres://postgres:postgres@db:5432/appdb")
        #expect(appContainer.configuration.initProcess.executable == "python -m http.server 8000")
        #expect(appContainer.configuration.platform.architecture == "arm64")
        #expect(appContainer.configuration.platform.os == "linux")
        
        // --- DB Container ---
        #expect(dbContainer.configuration.image.reference == "docker.io/library/postgres:14")
        let dbEnv = parseEnvToDict(dbContainer.configuration.initProcess.environment)
        #expect(dbEnv["POSTGRES_DB"] == "appdb")
        #expect(dbEnv["POSTGRES_USER"] == "postgres")
        #expect(dbEnv["POSTGRES_PASSWORD"] == "postgres")
        
        // --- Dependency Verification ---
        // The dependency chain should reflect: web → app → db
        // i.e., app depends on db, web depends on app
        // We can verify indirectly by container states and environment linkage.
        // App isn't set to run long term
        #expect(webContainer.status == .running)
        #expect(dbContainer.status == .running)
    }
    
    enum Errors: Error {
        case containerNotFound
    }
    
    private func parseEnvToDict(_ envArray: [String]) -> [String: String] {
        let array = envArray.map({ (String($0.split(separator: "=")[0]), String($0.split(separator: "=")[1])) })
        let dict = Dictionary(uniqueKeysWithValues: array)
        
        return dict
    }
}

struct ContainerDependentTrait: TestScoping, TestTrait, SuiteTrait {
    func provideScope(for test: Test, testCase: Test.Case?, performing function: () async throws -> Void) async throws {
        // Start Server
        try await Application.SystemStart.parse(["--enable-kernel-install"]).run()
        
        // Run Test
        try await function()
    }
}

extension Trait where Self == ContainerDependentTrait {
    static var containerDependent: ContainerDependentTrait { .init() }
}
