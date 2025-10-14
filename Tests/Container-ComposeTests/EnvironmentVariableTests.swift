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

@Suite("Environment Variable Resolution Tests")
struct EnvironmentVariableTests {
    
    @Test("Resolve simple variable")
    func resolveSimpleVariable() {
        let envVars = ["DATABASE_URL": "postgres://localhost/mydb"]
        let input = "${DATABASE_URL}"
        let result = resolveVariable(input, with: envVars)
        
        #expect(result == "postgres://localhost/mydb")
    }
    
    @Test("Resolve variable with default value when variable exists")
    func resolveVariableWithDefaultWhenExists() {
        let envVars = ["PORT": "8080"]
        let input = "${PORT:-3000}"
        let result = resolveVariable(input, with: envVars)
        
        #expect(result == "8080")
    }
    
    @Test("Use default value when variable does not exist")
    func useDefaultWhenVariableDoesNotExist() {
        let envVars: [String: String] = [:]
        let input = "${PORT:-3000}"
        let result = resolveVariable(input, with: envVars)
        
        #expect(result == "3000")
    }
    
    @Test("Resolve multiple variables in string")
    func resolveMultipleVariables() {
        let envVars = [
            "HOST": "localhost",
            "PORT": "5432",
            "DATABASE": "mydb"
        ]
        let input = "postgres://${HOST}:${PORT}/${DATABASE}"
        let result = resolveVariable(input, with: envVars)
        
        #expect(result == "postgres://localhost:5432/mydb")
    }
    
    @Test("Leave unresolved variable when no default provided")
    func leaveUnresolvedVariable() {
        let envVars: [String: String] = [:]
        let input = "${UNDEFINED_VAR}"
        let result = resolveVariable(input, with: envVars)
        
        // Should leave as-is when variable not found and no default
        #expect(result == "${UNDEFINED_VAR}")
    }
    
    @Test("Resolve with empty default value")
    func resolveWithEmptyDefault() {
        let envVars: [String: String] = [:]
        let input = "${OPTIONAL_VAR:-}"
        let result = resolveVariable(input, with: envVars)
        
        #expect(result == "")
    }
    
    @Test("Resolve complex string with mixed content")
    func resolveComplexString() {
        let envVars = ["VERSION": "1.2.3"]
        let input = "MyApp version ${VERSION} (build 42)"
        let result = resolveVariable(input, with: envVars)
        
        #expect(result == "MyApp version 1.2.3 (build 42)")
    }
    
    @Test("Variable names are case-sensitive")
    func caseSensitiveVariableNames() {
        let envVars = ["myvar": "lowercase", "MYVAR": "uppercase"]
        let input1 = "${myvar}"
        let input2 = "${MYVAR}"
        
        let result1 = resolveVariable(input1, with: envVars)
        let result2 = resolveVariable(input2, with: envVars)
        
        #expect(result1 == "lowercase")
        #expect(result2 == "uppercase")
    }
    
    @Test("Resolve variables with underscores and numbers")
    func resolveVariablesWithUnderscoresAndNumbers() {
        let envVars = ["VAR_NAME_123": "value123"]
        let input = "${VAR_NAME_123}"
        let result = resolveVariable(input, with: envVars)
        
        #expect(result == "value123")
    }
    
    @Test("Process environment takes precedence over provided envVars")
    func processEnvironmentTakesPrecedence() {
        // This test assumes PATH exists in process environment
        let envVars = ["PATH": "custom-path"]
        let input = "${PATH}"
        let result = resolveVariable(input, with: envVars)
        
        // Should use process environment, not custom value
        #expect(result != "custom-path")
        #expect(result.isEmpty == false)
    }
    
    @Test("Resolve variable that is part of larger text")
    func resolveVariableInLargerText() {
        let envVars = ["API_KEY": "secret123"]
        let input = "Authorization: Bearer ${API_KEY}"
        let result = resolveVariable(input, with: envVars)
        
        #expect(result == "Authorization: Bearer secret123")
    }
    
    @Test("No variables to resolve returns original string")
    func noVariablesToResolve() {
        let envVars = ["KEY": "value"]
        let input = "This is a plain string"
        let result = resolveVariable(input, with: envVars)
        
        #expect(result == "This is a plain string")
    }
}

// Test helper function that mimics the actual implementation
func resolveVariable(_ value: String, with envVars: [String: String]) -> String {
    var resolvedValue = value
    let regex = try! NSRegularExpression(pattern: "\\$\\{([A-Z0-9_]+)(:?-(.*?))?(:\\?(.*?))?\\}", options: [])
    
    let combinedEnv = ProcessInfo.processInfo.environment.merging(envVars) { (current, _) in current }
    
    while let match = regex.firstMatch(in: resolvedValue, options: [], range: NSRange(resolvedValue.startIndex..<resolvedValue.endIndex, in: resolvedValue)) {
        guard let varNameRange = Range(match.range(at: 1), in: resolvedValue) else { break }
        let varName = String(resolvedValue[varNameRange])
        
        if let envValue = combinedEnv[varName] {
            resolvedValue.replaceSubrange(Range(match.range(at: 0), in: resolvedValue)!, with: envValue)
        } else if let defaultValueRange = Range(match.range(at: 3), in: resolvedValue) {
            let defaultValue = String(resolvedValue[defaultValueRange])
            resolvedValue.replaceSubrange(Range(match.range(at: 0), in: resolvedValue)!, with: defaultValue)
        } else if match.range(at: 5).location != NSNotFound, let errorMessageRange = Range(match.range(at: 5), in: resolvedValue) {
            // In tests we'll skip the exit behavior
            break
        } else {
            break
        }
    }
    return resolvedValue
}
