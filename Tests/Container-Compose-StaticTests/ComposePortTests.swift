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

struct ComposePortTests {
    @Test(arguments: [
        ("0.0.0.0", "0.0.0.0:15432"),
        ("::", "[::]:15432"),
        ("[::1]", "[::1]:15432"),
    ])
    func formatsPublishedEndpoint(host: String, expected: String) {
        #expect(ComposePort.endpoint(host: host, port: 15432) == expected)
    }

    @Test(arguments: [
        (UInt16(79), nil as UInt16?),
        (UInt16(80), UInt16(15432) as UInt16?),
        (UInt16(82), UInt16(15434) as UInt16?),
        (UInt16(83), nil as UInt16?),
    ])
    func resolvesPortInPublishedRange(port: UInt16, expected: UInt16?) {
        #expect(ComposePort.publishedPort(for: port, containerStart: 80, hostStart: 15432, count: 3) == expected)
    }
}
