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

@Suite("Environment File Loading Tests")
struct EnvFileLoadingTests {
    
    @Test("Load simple key-value pairs from .env file")
    func loadSimpleEnvFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let envFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).env")
        
        let content = """
        DATABASE_URL=postgres://localhost/mydb
        PORT=8080
        DEBUG=true
        """
        
        try content.write(to: envFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: envFile) }
        
        let envVars = loadEnvFile(path: envFile.path)
        
        #expect(envVars["DATABASE_URL"] == "postgres://localhost/mydb")
        #expect(envVars["PORT"] == "8080")
        #expect(envVars["DEBUG"] == "true")
        #expect(envVars.count == 3)
    }
    
    @Test("Ignore comments in .env file")
    func ignoreComments() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let envFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).env")
        
        let content = """
        # This is a comment
        DATABASE_URL=postgres://localhost/mydb
        # Another comment
        PORT=8080
        """
        
        try content.write(to: envFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: envFile) }
        
        let envVars = loadEnvFile(path: envFile.path)
        
        #expect(envVars["DATABASE_URL"] == "postgres://localhost/mydb")
        #expect(envVars["PORT"] == "8080")
        #expect(envVars.count == 2)
    }
    
    @Test("Ignore empty lines in .env file")
    func ignoreEmptyLines() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let envFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).env")
        
        let content = """
        DATABASE_URL=postgres://localhost/mydb
        
        PORT=8080
        
        DEBUG=true
        """
        
        try content.write(to: envFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: envFile) }
        
        let envVars = loadEnvFile(path: envFile.path)
        
        #expect(envVars.count == 3)
    }
    
    @Test("Handle values with equals signs")
    func handleValuesWithEquals() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let envFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).env")
        
        let content = """
        CONNECTION_STRING=Server=localhost;Database=mydb;User=admin
        """
        
        try content.write(to: envFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: envFile) }
        
        let envVars = loadEnvFile(path: envFile.path)
        
        #expect(envVars["CONNECTION_STRING"] == "Server=localhost;Database=mydb;User=admin")
    }
    
    @Test("Handle empty values")
    func handleEmptyValues() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let envFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).env")
        
        let content = """
        EMPTY_VAR=
        NORMAL_VAR=value
        """
        
        try content.write(to: envFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: envFile) }
        
        let envVars = loadEnvFile(path: envFile.path)
        
        #expect(envVars["EMPTY_VAR"] == "")
        #expect(envVars["NORMAL_VAR"] == "value")
    }
    
    @Test("Handle values with spaces")
    func handleValuesWithSpaces() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let envFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).env")
        
        let content = """
        MESSAGE=Hello World
        PATH_WITH_SPACES=/path/to/some directory
        """
        
        try content.write(to: envFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: envFile) }
        
        let envVars = loadEnvFile(path: envFile.path)
        
        #expect(envVars["MESSAGE"] == "Hello World")
        #expect(envVars["PATH_WITH_SPACES"] == "/path/to/some directory")
    }
    
    @Test("Return empty dict for non-existent file")
    func returnEmptyDictForNonExistentFile() {
        let nonExistentPath = "/tmp/non-existent-\(UUID().uuidString).env"
        let envVars = loadEnvFile(path: nonExistentPath)
        
        #expect(envVars.isEmpty)
    }
    
    @Test("Handle mixed content")
    func handleMixedContent() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let envFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).env")
        
        let content = """
        # Application Configuration
        APP_NAME=MyApp
        
        # Database Settings
        DATABASE_URL=postgres://localhost/mydb
        DB_POOL_SIZE=10
        
        # Empty value
        OPTIONAL_VAR=
        
        # Comment at end
        """
        
        try content.write(to: envFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: envFile) }
        
        let envVars = loadEnvFile(path: envFile.path)
        
        #expect(envVars["APP_NAME"] == "MyApp")
        #expect(envVars["DATABASE_URL"] == "postgres://localhost/mydb")
        #expect(envVars["DB_POOL_SIZE"] == "10")
        #expect(envVars["OPTIONAL_VAR"] == "")
        #expect(envVars.count == 4)
    }
}

// Test helper function that mimics the actual implementation
