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
@testable import Yams
@testable import ContainerComposeCore

@Suite("Compose Up Tests - Real-World Compose Files", .containerDependent)
struct IntegrationTests {
    
    @Test("Parse WordPress with MySQL compose file")
    func parseWordPressCompose() async throws {
        let yaml = DockerComposeParsingTests.dockerComposeYaml1
        
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
        let wpEnvArray = wordpressContainer.configuration.initProcess.environment.map({ (String($0.split(separator: "=")[0]), String($0.split(separator: "=")[1])) })
        let wpEnv = Dictionary(uniqueKeysWithValues: wpEnvArray)
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
        let dbEnvArray = dbContainer.configuration.initProcess.environment.map({ (String($0.split(separator: "=")[0]), String($0.split(separator: "=")[1])) })
        let dbEnv = Dictionary(uniqueKeysWithValues: dbEnvArray)
        #expect(dbEnv["MYSQL_ROOT_PASSWORD"] == "rootpassword")
        #expect(dbEnv["MYSQL_DATABASE"] == "wordpress")
        #expect(dbEnv["MYSQL_USER"] == "wordpress")
        #expect(dbEnv["MYSQL_PASSWORD"] == "wordpress")
        
        // Check Volume
        #expect(dbContainer.configuration.mounts.map(\.destination) == ["/var/lib/"])
        print("")
    }
    
    @Test("Parse three-tier web application")
    func parseThreeTierApp() throws {
        let yaml = DockerComposeParsingTests.dockerComposeYaml2
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.name == "webapp")
        #expect(compose.services.count == 4)
        #expect(compose.networks?.count == 2)
        #expect(compose.volumes?.count == 1)
    }
    
    @Test("Parse microservices architecture")
    func parseMicroservicesCompose() throws {
        let yaml = DockerComposeParsingTests.dockerComposeYaml3
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services.count == 5)
        #expect(compose.services["api-gateway"]??.depends_on?.count == 3)
    }
    
    @Test("Parse development environment with build")
    func parseDevelopmentEnvironment() throws {
        let yaml = DockerComposeParsingTests.dockerComposeYaml4
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["app"]??.build != nil)
        #expect(compose.services["app"]??.build?.context == ".")
        #expect(compose.services["app"]??.volumes?.count == 2)
    }
    
    @Test("Parse compose with secrets and configs")
    func parseComposeWithSecretsAndConfigs() throws {
        let yaml = DockerComposeParsingTests.dockerComposeYaml5
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.configs != nil)
        #expect(compose.secrets != nil)
    }
    
    @Test("Parse compose with healthchecks and restart policies")
    func parseComposeWithHealthchecksAndRestart() throws {
        let yaml = DockerComposeParsingTests.dockerComposeYaml6
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(DockerCompose.self, from: yaml)
        
        #expect(compose.services["web"]??.restart == "unless-stopped")
        #expect(compose.services["web"]??.healthcheck != nil)
        #expect(compose.services["db"]??.restart == "always")
    }
    
    @Test("Parse compose with complex dependency chain")
    func parseComplexDependencyChain() async throws {
        let yaml = DockerComposeParsingTests.dockerComposeYaml7
        
        #expect(false)
    }
    
    enum Errors: Error {
        case containerNotFound
    }
}

struct ContainerDependentTrait: TestScoping, TestTrait, SuiteTrait {
    func provideScope(for test: Test, testCase: Test.Case?, performing function: () async throws -> Void) async throws {
        // Start Server
        try await Application.SystemStart.parse([]).run()
        
        // Run Test
        try await function()
    }
}

extension Trait where Self == ContainerDependentTrait {
    static var containerDependent: ContainerDependentTrait { .init() }
}
