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
import Yams
@testable import ContainerComposeCore

@Suite("Service labels")
struct ServiceLabelsTests {
    @Test func listLabels() throws {
        let service = try YAMLDecoder().decode(Service.self, from: """
        image: alpine
        labels:
          - role=worker
          - empty
          - explicit=
          - expression=a=b
          - role=web
        """)
        #expect(service.labels == ["role": "web", "empty": "", "explicit": "", "expression": "a=b"])
    }

    @Test(arguments: ["null", "{}", "{role: web}"])
    func mappingAndNull(value: String) throws {
        let service = try YAMLDecoder().decode(Service.self, from: "image: alpine\nlabels: \(value)")
        #expect(service.labels == (value == "null" ? nil : value == "{}" ? [:] : ["role": "web"]))
    }

    @Test(arguments: ["scalar", "[{nested: value}]", "{role: [nested]}"])
    func invalidLabels(value: String) {
        #expect(throws: (any Error).self) {
            try YAMLDecoder().decode(Service.self, from: "image: alpine\nlabels: \(value)")
        }
    }
}
