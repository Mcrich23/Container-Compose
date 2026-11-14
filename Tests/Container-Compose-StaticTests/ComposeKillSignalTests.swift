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

@Suite("Compose Kill Signal Tests")
struct ComposeKillSignalTests {

    @Test("SIGKILL / KILL / 9 map to 9")
    func testKill() {
        #expect(ComposeKill.signalNumber(for: "SIGKILL") == 9)
        #expect(ComposeKill.signalNumber(for: "KILL") == 9)
        #expect(ComposeKill.signalNumber(for: "9") == 9)
    }

    @Test("SIGTERM / TERM / 15 map to 15")
    func testTerm() {
        #expect(ComposeKill.signalNumber(for: "SIGTERM") == 15)
        #expect(ComposeKill.signalNumber(for: "TERM") == 15)
        #expect(ComposeKill.signalNumber(for: "15") == 15)
    }

    @Test("SIGINT / INT map to 2")
    func testInt() {
        #expect(ComposeKill.signalNumber(for: "SIGINT") == 2)
        #expect(ComposeKill.signalNumber(for: "INT") == 2)
    }

    @Test("SIGHUP / HUP map to 1")
    func testHup() {
        #expect(ComposeKill.signalNumber(for: "SIGHUP") == 1)
        #expect(ComposeKill.signalNumber(for: "HUP") == 1)
    }

    @Test("SIGQUIT / QUIT map to 3")
    func testQuit() {
        #expect(ComposeKill.signalNumber(for: "SIGQUIT") == 3)
        #expect(ComposeKill.signalNumber(for: "QUIT") == 3)
    }

    @Test("Unrecognized signal name defaults to SIGKILL (9)")
    func testUnknownDefaultsToKill() {
        #expect(ComposeKill.signalNumber(for: "BOGUS") == 9)
        #expect(ComposeKill.signalNumber(for: "") == 9)
    }

    @Test("Mapping is case-insensitive")
    func testCaseInsensitive() {
        #expect(ComposeKill.signalNumber(for: "sigkill") == 9)
        #expect(ComposeKill.signalNumber(for: "Term") == 15)
        #expect(ComposeKill.signalNumber(for: "sigint") == 2)
    }

    @Test("Numeric strings are parsed directly")
    func testNumericPassthrough() {
        #expect(ComposeKill.signalNumber(for: "2") == 2)
        #expect(ComposeKill.signalNumber(for: "30") == 30)
    }

    @Test("Surrounding whitespace is trimmed")
    func testWhitespaceTrimmed() {
        #expect(ComposeKill.signalNumber(for: "  SIGTERM  ") == 15)
        #expect(ComposeKill.signalNumber(for: " 9 ") == 9)
    }
}
