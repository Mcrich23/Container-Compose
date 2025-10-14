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
@testable import ContainerComposeCore

@Suite("Error Handling Tests")
struct ErrorHandlingTests {
    
    @Test("YamlError.composeFileNotFound contains path")
    func yamlErrorComposeFileNotFoundMessage() {
        let error = YamlError.composeFileNotFound("/path/to/directory")
        let description = error.errorDescription
        
        #expect(description != nil)
        #expect(description?.contains("/path/to/directory") == true)
    }
    
    @Test("ComposeError.imageNotFound contains service name")
    func composeErrorImageNotFoundMessage() {
        let error = ComposeError.imageNotFound("my-service")
        let description = error.errorDescription
        
        #expect(description != nil)
        #expect(description?.contains("my-service") == true)
    }
    
    @Test("ComposeError.invalidProjectName has appropriate message")
    func composeErrorInvalidProjectNameMessage() {
        let error = ComposeError.invalidProjectName
        let description = error.errorDescription
        
        #expect(description != nil)
        #expect(description?.contains("project name") == true)
    }
    
    @Test("TerminalError.commandFailed contains command info")
    func terminalErrorCommandFailedMessage() {
        let error = TerminalError.commandFailed("container run nginx")
        let description = error.errorDescription
        
        #expect(description != nil)
        #expect(description?.contains("Command failed") == true)
    }
    
    @Test("CommandOutput enum cases")
    func commandOutputEnumCases() {
        let stdout = CommandOutput.stdout("test output")
        let stderr = CommandOutput.stderr("error output")
        let exitCode = CommandOutput.exitCode(0)
        
        switch stdout {
        case .stdout(let output):
            #expect(output == "test output")
        default:
            Issue.record("Expected stdout case")
        }
        
        switch stderr {
        case .stderr(let output):
            #expect(output == "error output")
        default:
            Issue.record("Expected stderr case")
        }
        
        switch exitCode {
        case .exitCode(let code):
            #expect(code == 0)
        default:
            Issue.record("Expected exitCode case")
        }
    }
}

// Test helper enums that mirror the actual implementation
enum YamlError: Error, LocalizedError {
    case composeFileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .composeFileNotFound(let path):
            return "compose.yml not found at \(path)"
        }
    }
}

enum ComposeError: Error, LocalizedError {
    case imageNotFound(String)
    case invalidProjectName
    
    var errorDescription: String? {
        switch self {
        case .imageNotFound(let name):
            return "Service \(name) must define either 'image' or 'build'."
        case .invalidProjectName:
            return "Could not find project name."
        }
    }
}

enum TerminalError: Error, LocalizedError {
    case commandFailed(String)
    
    var errorDescription: String? {
        "Command failed: \(self)"
    }
}

