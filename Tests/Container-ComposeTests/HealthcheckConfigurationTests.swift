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

@Suite("Healthcheck Configuration Tests")
struct HealthcheckConfigurationTests {
    
    @Test("Parse healthcheck with test command")
    func parseHealthcheckWithTest() throws {
        let yaml = """
        test: ["CMD", "curl", "-f", "http://localhost"]
        """
        
        let decoder = YAMLDecoder()
        let healthcheck = try decoder.decode(Healthcheck.self, from: yaml)
        
        #expect(healthcheck.test?.count == 4)
        #expect(healthcheck.test?.first == "CMD")
    }
    
    @Test("Parse healthcheck with interval")
    func parseHealthcheckWithInterval() throws {
        let yaml = """
        test: ["CMD", "curl", "-f", "http://localhost"]
        interval: 30s
        """
        
        let decoder = YAMLDecoder()
        let healthcheck = try decoder.decode(Healthcheck.self, from: yaml)
        
        #expect(healthcheck.interval == "30s")
    }
    
    @Test("Parse healthcheck with timeout")
    func parseHealthcheckWithTimeout() throws {
        let yaml = """
        test: ["CMD", "curl", "-f", "http://localhost"]
        timeout: 10s
        """
        
        let decoder = YAMLDecoder()
        let healthcheck = try decoder.decode(Healthcheck.self, from: yaml)
        
        #expect(healthcheck.timeout == "10s")
    }
    
    @Test("Parse healthcheck with retries")
    func parseHealthcheckWithRetries() throws {
        let yaml = """
        test: ["CMD", "curl", "-f", "http://localhost"]
        retries: 3
        """
        
        let decoder = YAMLDecoder()
        let healthcheck = try decoder.decode(Healthcheck.self, from: yaml)
        
        #expect(healthcheck.retries == 3)
    }
    
    @Test("Parse healthcheck with start_period")
    func parseHealthcheckWithStartPeriod() throws {
        let yaml = """
        test: ["CMD", "curl", "-f", "http://localhost"]
        start_period: 40s
        """
        
        let decoder = YAMLDecoder()
        let healthcheck = try decoder.decode(Healthcheck.self, from: yaml)
        
        #expect(healthcheck.start_period == "40s")
    }
    
    @Test("Parse complete healthcheck configuration")
    func parseCompleteHealthcheck() throws {
        let yaml = """
        test: ["CMD", "curl", "-f", "http://localhost"]
        interval: 30s
        timeout: 10s
        retries: 3
        start_period: 40s
        """
        
        let decoder = YAMLDecoder()
        let healthcheck = try decoder.decode(Healthcheck.self, from: yaml)
        
        #expect(healthcheck.test != nil)
        #expect(healthcheck.interval == "30s")
        #expect(healthcheck.timeout == "10s")
        #expect(healthcheck.retries == 3)
        #expect(healthcheck.start_period == "40s")
    }
    
    @Test("Parse healthcheck with CMD-SHELL")
    func parseHealthcheckWithCmdShell() throws {
        let yaml = """
        test: ["CMD-SHELL", "curl -f http://localhost || exit 1"]
        """
        
        let decoder = YAMLDecoder()
        let healthcheck = try decoder.decode(Healthcheck.self, from: yaml)
        
        #expect(healthcheck.test?.first == "CMD-SHELL")
    }
    
    @Test("Disable healthcheck")
    func disableHealthcheck() throws {
        let yaml = """
        test: ["NONE"]
        """
        
        let decoder = YAMLDecoder()
        let healthcheck = try decoder.decode(Healthcheck.self, from: yaml)
        
        #expect(healthcheck.test?.first == "NONE")
    }
    
    @Test("Service with healthcheck")
    func serviceWithHealthcheck() throws {
        let yaml = """
        version: '3.8'
        services:
          web:
            image: nginx:latest
            healthcheck:
              test: ["CMD", "curl", "-f", "http://localhost"]
              interval: 30s
              timeout: 10s
              retries: 3
        """
        
        let decoder = YAMLDecoder()
        let compose = try decoder.decode(TestDockerCompose.self, from: yaml)
        
        #expect(compose.services["web"]?.healthcheck != nil)
        #expect(compose.services["web"]?.healthcheck?.interval == "30s")
    }
}

// Test helper structs
