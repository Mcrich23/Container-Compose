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

import Foundation
import Testing

@testable import ContainerComposeCore

@Suite("Helper Functions Tests")
struct HelperFunctionsTests {

   @Test("Derive project name from current working directory - contains dot")
   func testDeriveProjectName() throws {
      var cwd = "/Users/user/Projects/My.Project"
      var projectName = deriveProjectName(cwd: cwd)
      #expect(projectName == "My_Project")

      cwd = ".devcontainers"
      projectName = deriveProjectName(cwd: cwd)
      #expect(projectName == "_devcontainers")
   }

   @Test("Compose port - simple container port")
   func testPortSimple() throws {
      let result = composePortToRunArg("3000")
      #expect(result == "0.0.0.0:3000:3000")
   }

   @Test("Compose port - host:container same port")
   func testPortHostContainerSame() throws {
      let result = composePortToRunArg("3000:3000")
      #expect(result == "0.0.0.0:3000:3000")
   }

   @Test("Compose port - host:container different ports")
   func testPortHostContainerDifferent() throws {
      let result = composePortToRunArg("8080:3000")
      #expect(result == "0.0.0.0:8080:3000")
   }

   @Test("Compose port - explicit IP binding IPv4")
   func testPortIPv4Binding() throws {
      let result = composePortToRunArg("127.0.0.1:5432:5432")
      #expect(result == "127.0.0.1:5432:5432")
   }

   @Test("Compose port - explicit IP binding IPv6")
   func testPortIPv6Binding() throws {
      let result = composePortToRunArg("[::1]:3000:3000")
      #expect(result == "[::1]:3000:3000")
   }

   @Test("Compose port - with protocol tcp")
   func testPortWithProtocolTCP() throws {
      let result = composePortToRunArg("3000:3000/tcp")
      #expect(result == "0.0.0.0:3000:3000/tcp")
   }

   @Test("Compose port - explicit IP with protocol")
   func testPortIPv4WithProtocol() throws {
      let result = composePortToRunArg("127.0.0.1:5432:5432/tcp")
      #expect(result == "127.0.0.1:5432:5432/tcp")
   }

   @Test("Compose port - explicit IP already with 0.0.0.0")
   func testPortZeroZeroZeroZero() throws {
      let result = composePortToRunArg("0.0.0.0:3000:3000")
      #expect(result == "0.0.0.0:3000:3000")
   }

}
