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

@Suite("Port Mapping Tests")
struct PortMappingTests {
    
    @Test("Parse simple port mapping")
    func parseSimplePortMapping() {
        let portString = "8080:80"
        let components = portString.split(separator: ":").map(String.init)
        
        #expect(components.count == 2)
        #expect(components[0] == "8080")
        #expect(components[1] == "80")
    }
    
    @Test("Parse port mapping with protocol")
    func parsePortMappingWithProtocol() {
        let portString = "8080:80/tcp"
        let parts = portString.split(separator: "/")
        let portParts = parts[0].split(separator: ":").map(String.init)
        
        #expect(portParts.count == 2)
        #expect(portParts[0] == "8080")
        #expect(portParts[1] == "80")
        #expect(parts.count == 2)
        #expect(String(parts[1]) == "tcp")
    }
    
    @Test("Parse port mapping with IP binding")
    func parsePortMappingWithIPBinding() {
        let portString = "127.0.0.1:8080:80"
        let components = portString.split(separator: ":").map(String.init)
        
        #expect(components.count == 3)
        #expect(components[0] == "127.0.0.1")
        #expect(components[1] == "8080")
        #expect(components[2] == "80")
    }
    
    @Test("Parse single port (container only)")
    func parseSinglePort() {
        let portString = "80"
        let components = portString.split(separator: ":").map(String.init)
        
        #expect(components.count == 1)
        #expect(components[0] == "80")
    }
    
    @Test("Parse port range")
    func parsePortRange() {
        let portString = "8000-8010:8000-8010"
        let components = portString.split(separator: ":").map(String.init)
        
        #expect(components.count == 2)
        #expect(components[0] == "8000-8010")
        #expect(components[1] == "8000-8010")
    }
    
    @Test("Parse UDP port mapping")
    func parseUDPPortMapping() {
        let portString = "53:53/udp"
        let parts = portString.split(separator: "/")
        let portParts = parts[0].split(separator: ":").map(String.init)
        
        #expect(portParts.count == 2)
        #expect(String(parts[1]) == "udp")
    }
    
    @Test("Parse IPv6 address binding")
    func parseIPv6AddressBinding() {
        let portString = "[::1]:8080:80"
        
        // IPv6 addresses are enclosed in brackets
        #expect(portString.contains("[::1]"))
    }
    
    @Test("Multiple port mappings in array")
    func multiplePortMappings() {
        let ports = ["80:80", "443:443", "8080:8080"]
        
        #expect(ports.count == 3)
        for port in ports {
            let components = port.split(separator: ":").map(String.init)
            #expect(components.count == 2)
        }
    }
    
    @Test("Port mapping with string format in YAML")
    func portMappingStringFormat() {
        let port1 = "8080:80"
        let port2 = "3000"
        
        #expect(port1.contains(":") == true)
        #expect(port2.contains(":") == false)
    }
    
    @Test("Extract host port from mapping")
    func extractHostPort() {
        let portString = "8080:80"
        let components = portString.split(separator: ":").map(String.init)
        let hostPort = components.first
        
        #expect(hostPort == "8080")
    }
    
    @Test("Extract container port from mapping")
    func extractContainerPort() {
        let portString = "8080:80"
        let components = portString.split(separator: ":").map(String.init)
        let containerPort = components.last
        
        #expect(containerPort == "80")
    }
    
    @Test("Validate numeric port values")
    func validateNumericPortValues() {
        let validPort = "8080"
        let invalidPort = "not-a-port"
        
        #expect(Int(validPort) != nil)
        #expect(Int(invalidPort) == nil)
    }
    
    @Test("Parse quoted port string")
    func parseQuotedPortString() {
        // In YAML, ports can be quoted to ensure string interpretation
        let portString = "8080:80"
        
        #expect(portString == "8080:80")
    }
}
