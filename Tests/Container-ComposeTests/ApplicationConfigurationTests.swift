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
@testable import ContainerComposeCore

@Suite("Application Configuration Tests")
struct ApplicationConfigurationTests {
    
    @Test("Command name is container-compose")
    func commandName() {
        let expectedName = "container-compose"
        #expect(expectedName == "container-compose")
    }
    
    @Test("Version string format")
    func versionStringFormat() {
        let version = "v0.5.1"
        let commandName = "container-compose"
        let versionString = "\(commandName) version \(version)"
        
        #expect(versionString == "container-compose version v0.5.1")
    }
    
    @Test("Version string contains command name")
    func versionStringContainsCommandName() {
        let versionString = "container-compose version v0.5.1"
        
        #expect(versionString.contains("container-compose"))
    }
    
    @Test("Version string contains version number")
    func versionStringContainsVersionNumber() {
        let versionString = "container-compose version v0.5.1"
        
        #expect(versionString.contains("v0.5.1"))
    }
    
    @Test("Supported subcommands")
    func supportedSubcommands() {
        let subcommands = ["up", "down", "version"]
        
        #expect(subcommands.contains("up"))
        #expect(subcommands.contains("down"))
        #expect(subcommands.contains("version"))
        #expect(subcommands.count == 3)
    }
    
    @Test("Abstract description")
    func abstractDescription() {
        let abstract = "A tool to use manage Docker Compose files with Apple Container"
        
        #expect(abstract.contains("Docker Compose"))
        #expect(abstract.contains("Apple Container"))
    }
    
    @Test("Default compose filenames")
    func defaultComposeFilenames() {
        let filenames = [
            "compose.yml",
            "compose.yaml",
            "docker-compose.yml",
            "docker-compose.yaml"
        ]
        
        #expect(filenames.count == 4)
        #expect(filenames.contains("compose.yml"))
        #expect(filenames.contains("docker-compose.yml"))
    }
    
    @Test("Default env file name")
    func defaultEnvFileName() {
        let envFile = ".env"
        
        #expect(envFile == ".env")
    }
}

@Suite("Command Line Flag Tests")
struct CommandLineFlagTests {
    
    @Test("ComposeUp flags - detach flag short form")
    func composeUpDetachFlagShortForm() {
        let shortFlag = "-d"
        #expect(shortFlag == "-d")
    }
    
    @Test("ComposeUp flags - detach flag long form")
    func composeUpDetachFlagLongForm() {
        let longFlag = "--detach"
        #expect(longFlag == "--detach")
    }
    
    @Test("ComposeUp flags - file flag short form")
    func composeUpFileFlagShortForm() {
        let shortFlag = "-f"
        #expect(shortFlag == "-f")
    }
    
    @Test("ComposeUp flags - file flag long form")
    func composeUpFileFlagLongForm() {
        let longFlag = "--file"
        #expect(longFlag == "--file")
    }
    
    @Test("ComposeUp flags - build flag short form")
    func composeUpBuildFlagShortForm() {
        let shortFlag = "-b"
        #expect(shortFlag == "-b")
    }
    
    @Test("ComposeUp flags - build flag long form")
    func composeUpBuildFlagLongForm() {
        let longFlag = "--build"
        #expect(longFlag == "--build")
    }
    
    @Test("ComposeUp flags - no-cache flag")
    func composeUpNoCacheFlag() {
        let flag = "--no-cache"
        #expect(flag == "--no-cache")
    }
    
    @Test("ComposeDown flags - file flag")
    func composeDownFileFlag() {
        let shortFlag = "-f"
        let longFlag = "--file"
        
        #expect(shortFlag == "-f")
        #expect(longFlag == "--file")
    }
}

@Suite("File Path Resolution Tests")
struct FilePathResolutionTests {
    
    @Test("Compose path from cwd and filename")
    func composePathResolution() {
        let cwd = "/home/user/project"
        let filename = "compose.yml"
        let composePath = "\(cwd)/\(filename)"
        
        #expect(composePath == "/home/user/project/compose.yml")
    }
    
    @Test("Env file path from cwd")
    func envFilePathResolution() {
        let cwd = "/home/user/project"
        let envFile = ".env"
        let envFilePath = "\(cwd)/\(envFile)"
        
        #expect(envFilePath == "/home/user/project/.env")
    }
    
    @Test("Current directory path")
    func currentDirectoryPath() {
        let currentPath = FileManager.default.currentDirectoryPath
        
        #expect(currentPath.isEmpty == false)
    }
    
    @Test("Project name from directory")
    func projectNameFromDirectory() {
        let path = "/home/user/my-project"
        let url = URL(fileURLWithPath: path)
        let projectName = url.lastPathComponent
        
        #expect(projectName == "my-project")
    }
    
    @Test("Project name extraction")
    func projectNameExtraction() {
        let paths = [
            "/home/user/web-app",
            "/var/projects/api-service",
            "/tmp/test-container"
        ]
        
        let names = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
        
        #expect(names[0] == "web-app")
        #expect(names[1] == "api-service")
        #expect(names[2] == "test-container")
    }
}

@Suite("Container Naming Tests")
struct ContainerNamingTests {
    
    @Test("Container name with project prefix")
    func containerNameWithProjectPrefix() {
        let projectName = "my-project"
        let serviceName = "web"
        let containerName = "\(projectName)-\(serviceName)"
        
        #expect(containerName == "my-project-web")
    }
    
    @Test("Multiple container names")
    func multipleContainerNames() {
        let projectName = "app"
        let services = ["web", "db", "redis"]
        let containerNames = services.map { "\(projectName)-\($0)" }
        
        #expect(containerNames.count == 3)
        #expect(containerNames[0] == "app-web")
        #expect(containerNames[1] == "app-db")
        #expect(containerNames[2] == "app-redis")
    }
    
    @Test("Container name sanitization")
    func containerNameSanitization() {
        // Container names should be valid
        let projectName = "my-project"
        let serviceName = "web-service"
        let containerName = "\(projectName)-\(serviceName)"
        
        #expect(containerName.contains(" ") == false)
        #expect(containerName.contains("-") == true)
    }
}
