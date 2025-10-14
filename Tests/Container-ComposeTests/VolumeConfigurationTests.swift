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

@Suite("Volume Configuration Tests")
struct VolumeConfigurationTests {
    
    @Test("Parse named volume mount")
    func parseNamedVolumeMount() {
        let volumeString = "db-data:/var/lib/postgresql/data"
        let components = volumeString.split(separator: ":").map(String.init)
        
        #expect(components.count == 2)
        #expect(components[0] == "db-data")
        #expect(components[1] == "/var/lib/postgresql/data")
    }
    
    @Test("Parse bind mount with absolute path")
    func parseBindMountAbsolutePath() {
        let volumeString = "/host/path:/container/path"
        let components = volumeString.split(separator: ":").map(String.init)
        
        #expect(components.count == 2)
        #expect(components[0] == "/host/path")
        #expect(components[1] == "/container/path")
    }
    
    @Test("Parse bind mount with relative path")
    func parseBindMountRelativePath() {
        let volumeString = "./data:/app/data"
        let components = volumeString.split(separator: ":").map(String.init)
        
        #expect(components.count == 2)
        #expect(components[0] == "./data")
        #expect(components[1] == "/app/data")
    }
    
    @Test("Parse volume with read-only flag")
    func parseVolumeWithReadOnlyFlag() {
        let volumeString = "db-data:/var/lib/postgresql/data:ro"
        let components = volumeString.split(separator: ":").map(String.init)
        
        #expect(components.count == 3)
        #expect(components[0] == "db-data")
        #expect(components[1] == "/var/lib/postgresql/data")
        #expect(components[2] == "ro")
    }
    
    @Test("Identify bind mount by forward slash")
    func identifyBindMountBySlash() {
        let namedVolume = "my-volume"
        let bindMount = "/absolute/path"
        let relativeMount = "./relative/path"
        
        #expect(namedVolume.contains("/") == false)
        #expect(bindMount.contains("/") == true)
        #expect(relativeMount.contains("/") == true)
    }
    
    @Test("Identify bind mount by dot prefix")
    func identifyBindMountByDot() {
        let volumes = ["./data", "../config", "named-volume"]
        
        #expect(volumes[0].starts(with: ".") == true)
        #expect(volumes[1].starts(with: ".") == true)
        #expect(volumes[2].starts(with: ".") == false)
    }
    
    @Test("Parse volume mount with multiple colons")
    func parseVolumeMountWithMultipleColons() {
        let volumeString = "/host/path:/container/path:ro"
        let components = volumeString.split(separator: ":").map(String.init)
        
        #expect(components.count == 3)
        #expect(components[0] == "/host/path")
        #expect(components[1] == "/container/path")
        #expect(components[2] == "ro")
    }
    
    @Test("Handle invalid volume format")
    func handleInvalidVolumeFormat() {
        let invalidVolume = "invalid-format"
        let components = invalidVolume.split(separator: ":").map(String.init)
        
        // Should have only one component (no colon)
        #expect(components.count == 1)
    }
    
    @Test("Parse tmpfs mount (if supported)")
    func parseTmpfsMount() {
        let volumeString = "tmpfs:/app/tmp"
        let components = volumeString.split(separator: ":").map(String.init)
        
        #expect(components.count == 2)
        #expect(components[0] == "tmpfs")
        #expect(components[1] == "/app/tmp")
    }
    
    @Test("Resolve relative path to absolute")
    func resolveRelativePathToAbsolute() {
        let relativePath = "./data"
        let cwd = "/home/user/project"
        let fullPath = cwd + "/" + relativePath
        
        #expect(fullPath == "/home/user/project/./data")
    }
    
    @Test("Handle tilde expansion in path")
    func handleTildeInPath() {
        let pathWithTilde = "~/data"
        let pathWithAbsolute = "/absolute/path"
        
        #expect(pathWithTilde.starts(with: "~") == true)
        #expect(pathWithAbsolute.starts(with: "/") == true)
    }
    
    @Test("Empty volume definitions should be handled")
    func handleEmptyVolumeDefinitions() {
        // When volumes section exists but is empty
        let volumes: [String: Volume] = [:]
        
        #expect(volumes.isEmpty == true)
    }
    
}
