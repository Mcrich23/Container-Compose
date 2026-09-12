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
@testable import ContainerComposeCore

@Suite("Compose ps Tests")
struct ComposePsTests {

    // MARK: - TableFormatter

    @Test("Table columns align and the trailing column is unpadded")
    func tableFormatting() {
        let out = TableFormatter.render(
            header: ["NAME", "STATUS"],
            rows: [["web", "running"], ["database", "stopped"]])
        let lines = out.split(separator: "\n").map(String.init)
        #expect(lines == [
            "NAME       STATUS",
            "web        running",
            "database   stopped",
        ])
    }

    // MARK: - CLI parsing

    @Test("ps accepts -a and service arguments alongside the project option group")
    func psParsesArguments() throws {
        let cmd = try ComposePs.parse(["-a", "web"])
        #expect(cmd.all)
        #expect(cmd.services == ["web"])
    }
}
