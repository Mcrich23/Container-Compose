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

@Suite("ComposeDown Command Tests")
struct ComposeDownTests {
    
    // MARK: - Command Configuration Tests
    
    @Test("Verify ComposeDown command name")
    func verifyCommandName() {
        #expect(ComposeDown.configuration.commandName == "down")
    }
    
    @Test("Verify ComposeDown has abstract description")
    func verifyAbstract() {
        #expect(ComposeDown.configuration.abstract != nil)
        #expect(ComposeDown.configuration.abstract?.isEmpty == false)
    }
    
    // MARK: - Flag Parsing Tests
    
    @Test("Parse ComposeDown with no flags")
    func parseComposeDownNoFlags() throws {
        let command = try ComposeDown.parse([])
        
        #expect(command.services.isEmpty)
        #expect(command.composeFilename == "compose.yml")
    }
    
    @Test("Parse ComposeDown with custom compose file (short form)")
    func parseComposeDownFileShort() throws {
        let command = try ComposeDown.parse(["-f", "custom-compose.yml"])
        
        #expect(command.composeFilename == "custom-compose.yml")
    }
    
    @Test("Parse ComposeDown with custom compose file (long form)")
    func parseComposeDownFileLong() throws {
        let command = try ComposeDown.parse(["--file", "docker-compose.prod.yml"])
        
        #expect(command.composeFilename == "docker-compose.prod.yml")
    }
    
    @Test("Parse ComposeDown with single service")
    func parseComposeDownSingleService() throws {
        let command = try ComposeDown.parse(["web"])
        
        #expect(command.services.count == 1)
        #expect(command.services.contains("web"))
    }
    
    @Test("Parse ComposeDown with multiple services")
    func parseComposeDownMultipleServices() throws {
        let command = try ComposeDown.parse(["web", "db", "cache"])
        
        #expect(command.services.count == 3)
        #expect(command.services.contains("web"))
        #expect(command.services.contains("db"))
        #expect(command.services.contains("cache"))
    }
    
    // MARK: - Combined Flags Tests
    
    @Test("Parse ComposeDown with file and services")
    func parseComposeDownFileAndServices() throws {
        let command = try ComposeDown.parse(["-f", "compose.prod.yml", "api", "worker"])
        
        #expect(command.composeFilename == "compose.prod.yml")
        #expect(command.services.count == 2)
        #expect(command.services.contains("api"))
        #expect(command.services.contains("worker"))
    }
    
    @Test("Parse ComposeDown with custom file and multiple services")
    func parseComposeDownFileMultipleServices() throws {
        let command = try ComposeDown.parse([
            "--file", "docker-compose.yml",
            "web", "api", "db", "cache"
        ])
        
        #expect(command.composeFilename == "docker-compose.yml")
        #expect(command.services.count == 4)
        #expect(command.services.contains("web"))
        #expect(command.services.contains("api"))
        #expect(command.services.contains("db"))
        #expect(command.services.contains("cache"))
    }
    
    // MARK: - Flag Combinations with Long and Short Forms
    
    @Test("Parse ComposeDown with short form file flag")
    func parseComposeDownShortFormFile() throws {
        let command = try ComposeDown.parse(["-f", "dev.yml"])
        
        #expect(command.composeFilename == "dev.yml")
    }
    
    @Test("Parse ComposeDown with long form file flag")
    func parseComposeDownLongFormFile() throws {
        let command = try ComposeDown.parse(["--file", "production.yml"])
        
        #expect(command.composeFilename == "production.yml")
    }
    
    // MARK: - Service Selection Tests
    
    @Test("Parse ComposeDown with single service name")
    func parseComposeDownSingleServiceName() throws {
        let command = try ComposeDown.parse(["database"])
        
        #expect(command.services.count == 1)
        #expect(command.services.first == "database")
    }
    
    @Test("Parse ComposeDown with many services")
    func parseComposeDownManyServices() throws {
        let command = try ComposeDown.parse([
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
    
    @Test("Parse ComposeDown with services at end")
    func parseComposeDownServicesAtEnd() throws {
        let command = try ComposeDown.parse(["-f", "compose.yml", "web", "api"])
        
        #expect(command.composeFilename == "compose.yml")
        #expect(command.services.count == 2)
        #expect(command.services.contains("web"))
        #expect(command.services.contains("api"))
    }
    
    // MARK: - File Path Tests
    
    @Test("Parse ComposeDown with relative file path")
    func parseComposeDownRelativeFile() throws {
        let command = try ComposeDown.parse(["-f", "./configs/compose.yml"])
        
        #expect(command.composeFilename == "./configs/compose.yml")
    }
    
    @Test("Parse ComposeDown with nested file path")
    func parseComposeDownNestedFile() throws {
        let command = try ComposeDown.parse(["--file", "docker/compose/prod.yml"])
        
        #expect(command.composeFilename == "docker/compose/prod.yml")
    }
    
    @Test("Parse ComposeDown with docker-compose.yml filename")
    func parseComposeDownDockerComposeFilename() throws {
        let command = try ComposeDown.parse(["-f", "docker-compose.yml"])
        
        #expect(command.composeFilename == "docker-compose.yml")
    }
    
    @Test("Parse ComposeDown with yaml extension")
    func parseComposeDownYamlExtension() throws {
        let command = try ComposeDown.parse(["--file", "compose.yaml"])
        
        #expect(command.composeFilename == "compose.yaml")
    }
    
    @Test("Parse ComposeDown with docker-compose.yaml filename")
    func parseComposeDownDockerComposeYamlFilename() throws {
        let command = try ComposeDown.parse(["-f", "docker-compose.yaml"])
        
        #expect(command.composeFilename == "docker-compose.yaml")
    }
    
    // MARK: - Complex Real-World Scenarios
    
    @Test("Parse ComposeDown production teardown scenario")
    func parseComposeDownProductionScenario() throws {
        let command = try ComposeDown.parse([
            "--file", "docker-compose.prod.yml",
            "web", "api", "worker"
        ])
        
        #expect(command.composeFilename == "docker-compose.prod.yml")
        #expect(command.services.count == 3)
        #expect(command.services.contains("web"))
        #expect(command.services.contains("api"))
        #expect(command.services.contains("worker"))
    }
    
    @Test("Parse ComposeDown development scenario")
    func parseComposeDownDevelopmentScenario() throws {
        let command = try ComposeDown.parse([
            "-f", "docker-compose.dev.yml",
            "web", "db"
        ])
        
        #expect(command.composeFilename == "docker-compose.dev.yml")
        #expect(command.services.count == 2)
        #expect(command.services.contains("web"))
        #expect(command.services.contains("db"))
    }
    
    @Test("Parse ComposeDown testing scenario")
    func parseComposeDownTestingScenario() throws {
        let command = try ComposeDown.parse([
            "--file", "docker-compose.test.yml"
        ])
        
        #expect(command.composeFilename == "docker-compose.test.yml")
        #expect(command.services.isEmpty) // Stop all services
    }
    
    @Test("Parse ComposeDown CI/CD cleanup scenario")
    func parseComposeDownCICDScenario() throws {
        let command = try ComposeDown.parse([
            "-f", "ci-compose.yml"
        ])
        
        #expect(command.composeFilename == "ci-compose.yml")
        #expect(command.services.isEmpty)
    }
    
    @Test("Parse ComposeDown selective service shutdown")
    func parseComposeDownSelectiveShutdown() throws {
        let command = try ComposeDown.parse(["web", "cache"])
        
        #expect(command.services.count == 2)
        #expect(command.services.contains("web"))
        #expect(command.services.contains("cache"))
        #expect(command.composeFilename == "compose.yml") // Default file
    }
    
    // MARK: - Edge Cases
    
    @Test("Parse ComposeDown with empty services array")
    func parseComposeDownEmptyServices() throws {
        let command = try ComposeDown.parse([])
        
        #expect(command.services.isEmpty)
    }
    
    @Test("Parse ComposeDown with duplicate file flags")
    func parseComposeDownDuplicateFlags() throws {
        // Last value should win
        let command = try ComposeDown.parse([
            "-f", "first.yml",
            "-f", "second.yml"
        ])
        
        #expect(command.composeFilename == "second.yml")
    }
    
    @Test("Parse ComposeDown with service names")
    func parseComposeDownServiceNames() throws {
        let command = try ComposeDown.parse(["frontend", "backend", "database"])
        
        #expect(command.services.count == 3)
        #expect(command.services.contains("frontend"))
        #expect(command.services.contains("backend"))
        #expect(command.services.contains("database"))
    }
    
    // MARK: - Default Values Tests
    
    @Test("Verify default compose filename")
    func verifyDefaultComposeFilename() throws {
        let command = try ComposeDown.parse([])
        
        #expect(command.composeFilename == "compose.yml")
    }
    
    @Test("Verify default services is empty")
    func verifyDefaultServices() throws {
        let command = try ComposeDown.parse([])
        
        #expect(command.services.isEmpty)
    }
    
    // MARK: - Flag Position Tests
    
    @Test("Parse ComposeDown with file flag at start")
    func parseComposeDownFileFlagStart() throws {
        let command = try ComposeDown.parse(["-f", "test.yml", "web"])
        
        #expect(command.composeFilename == "test.yml")
        #expect(command.services.contains("web"))
    }
    
    @Test("Parse ComposeDown with file flag in middle")
    func parseComposeDownFileFlagMiddle() throws {
        let command = try ComposeDown.parse(["web", "-f", "test.yml", "api"])
        
        #expect(command.composeFilename == "test.yml")
        #expect(command.services.contains("web"))
        #expect(command.services.contains("api"))
    }
    
    // MARK: - Multiple Service Combinations
    
    @Test("Parse ComposeDown with two services")
    func parseComposeDownTwoServices() throws {
        let command = try ComposeDown.parse(["api", "db"])
        
        #expect(command.services.count == 2)
        #expect(command.services.contains("api"))
        #expect(command.services.contains("db"))
    }
    
    @Test("Parse ComposeDown with three services")
    func parseComposeDownThreeServices() throws {
        let command = try ComposeDown.parse(["web", "api", "db"])
        
        #expect(command.services.count == 3)
        #expect(command.services.contains("web"))
        #expect(command.services.contains("api"))
        #expect(command.services.contains("db"))
    }
    
    @Test("Parse ComposeDown with four services")
    func parseComposeDownFourServices() throws {
        let command = try ComposeDown.parse(["web", "api", "db", "cache"])
        
        #expect(command.services.count == 4)
        #expect(command.services.contains("web"))
        #expect(command.services.contains("api"))
        #expect(command.services.contains("db"))
        #expect(command.services.contains("cache"))
    }
    
    // MARK: - File Path Variations
    
    @Test("Parse ComposeDown with absolute path")
    func parseComposeDownAbsolutePath() throws {
        let command = try ComposeDown.parse(["-f", "/path/to/compose.yml"])
        
        #expect(command.composeFilename == "/path/to/compose.yml")
    }
    
    @Test("Parse ComposeDown with parent directory path")
    func parseComposeDownParentPath() throws {
        let command = try ComposeDown.parse(["--file", "../compose.yml"])
        
        #expect(command.composeFilename == "../compose.yml")
    }
    
    @Test("Parse ComposeDown with current directory path")
    func parseComposeDownCurrentPath() throws {
        let command = try ComposeDown.parse(["-f", "./compose.yml"])
        
        #expect(command.composeFilename == "./compose.yml")
    }
    
    // MARK: - Service Name Variations
    
    @Test("Parse ComposeDown with hyphenated service names")
    func parseComposeDownHyphenatedServices() throws {
        let command = try ComposeDown.parse(["web-server", "api-gateway"])
        
        #expect(command.services.count == 2)
        #expect(command.services.contains("web-server"))
        #expect(command.services.contains("api-gateway"))
    }
    
    @Test("Parse ComposeDown with underscored service names")
    func parseComposeDownUnderscoredServices() throws {
        let command = try ComposeDown.parse(["web_server", "api_gateway"])
        
        #expect(command.services.count == 2)
        #expect(command.services.contains("web_server"))
        #expect(command.services.contains("api_gateway"))
    }
    
    @Test("Parse ComposeDown with numeric service names")
    func parseComposeDownNumericServices() throws {
        let command = try ComposeDown.parse(["service1", "service2", "service3"])
        
        #expect(command.services.count == 3)
        #expect(command.services.contains("service1"))
        #expect(command.services.contains("service2"))
        #expect(command.services.contains("service3"))
    }
    
    // MARK: - Flag Permutations
    
    @Test("Parse ComposeDown flag permutation 1")
    func parseComposeDownPermutation1() throws {
        let command = try ComposeDown.parse(["-f", "test.yml", "web"])
        
        #expect(command.composeFilename == "test.yml")
        #expect(command.services.contains("web"))
    }
    
    @Test("Parse ComposeDown flag permutation 2")
    func parseComposeDownPermutation2() throws {
        let command = try ComposeDown.parse(["web", "-f", "test.yml"])
        
        #expect(command.composeFilename == "test.yml")
        #expect(command.services.contains("web"))
    }
    
    @Test("Parse ComposeDown flag permutation 3")
    func parseComposeDownPermutation3() throws {
        let command = try ComposeDown.parse(["--file", "prod.yml", "api", "db"])
        
        #expect(command.composeFilename == "prod.yml")
        #expect(command.services.count == 2)
        #expect(command.services.contains("api"))
        #expect(command.services.contains("db"))
    }
    
    @Test("Parse ComposeDown flag permutation 4")
    func parseComposeDownPermutation4() throws {
        let command = try ComposeDown.parse(["api", "--file", "prod.yml", "db"])
        
        #expect(command.composeFilename == "prod.yml")
        #expect(command.services.count == 2)
        #expect(command.services.contains("api"))
        #expect(command.services.contains("db"))
    }
    
    @Test("Parse ComposeDown flag permutation 5")
    func parseComposeDownPermutation5() throws {
        let command = try ComposeDown.parse(["api", "db", "-f", "prod.yml"])
        
        #expect(command.composeFilename == "prod.yml")
        #expect(command.services.count == 2)
        #expect(command.services.contains("api"))
        #expect(command.services.contains("db"))
    }
    
    // MARK: - Stop All vs Selective Tests
    
    @Test("Parse ComposeDown stop all services")
    func parseComposeDownStopAll() throws {
        let command = try ComposeDown.parse(["-f", "compose.yml"])
        
        #expect(command.composeFilename == "compose.yml")
        #expect(command.services.isEmpty) // Empty means stop all
    }
    
    @Test("Parse ComposeDown stop selective services")
    func parseComposeDownStopSelective() throws {
        let command = try ComposeDown.parse(["-f", "compose.yml", "web", "api"])
        
        #expect(command.composeFilename == "compose.yml")
        #expect(command.services.count == 2) // Only specific services
    }
    
    @Test("Parse ComposeDown default file stop all")
    func parseComposeDownDefaultFileStopAll() throws {
        let command = try ComposeDown.parse([])
        
        #expect(command.composeFilename == "compose.yml")
        #expect(command.services.isEmpty)
    }
    
    @Test("Parse ComposeDown default file stop selective")
    func parseComposeDownDefaultFileStopSelective() throws {
        let command = try ComposeDown.parse(["web"])
        
        #expect(command.composeFilename == "compose.yml")
        #expect(command.services.count == 1)
        #expect(command.services.contains("web"))
    }
}
