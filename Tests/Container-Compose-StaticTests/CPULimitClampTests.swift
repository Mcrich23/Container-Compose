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
import Foundation
@testable import Yams
@testable import ContainerComposeCore

/// Companion to the memory floor in `clampMemoryLimit`: `container run --cpus`
/// takes a whole number while Compose allows a fraction, so the value has to be
/// adjusted and the adjustment reported.
@Suite("CPU Limit Clamping")
struct CPULimitClampTests {

    @Test("a fraction rounds up to the smallest expressible limit")
    func fractionRoundsUp() {
        let (value, clamped) = ComposeUp.clampCPULimit("0.5")
        #expect(value == "1")
        #expect(clamped)
    }

    @Test("rounding is up, never down to zero")
    func neverZero() {
        // 0.1 down would be 0, which `container run` rejects outright.
        #expect(ComposeUp.clampCPULimit("0.1").value == "1")
        #expect(ComposeUp.clampCPULimit("0").value == "1")
        for (input, expected) in [("1.5", "2"), ("2.5", "3"), ("3.01", "4")] {
            #expect(ComposeUp.clampCPULimit(input).value == expected, "\(input)")
        }
    }

    @Test("whole numbers are passed through untouched and unreported")
    func wholeNumbersUnchanged() {
        for input in ["1", "2", "4", "16"] {
            let (value, clamped) = ComposeUp.clampCPULimit(input)
            #expect(value == input, "\(input)")
            #expect(clamped == false, "\(input) should not be reported as clamped")
        }
    }

    @Test("an unparseable value is left alone rather than guessed at")
    func unparseablePassesThrough() {
        let (value, clamped) = ComposeUp.clampCPULimit("not-a-number")
        #expect(value == "not-a-number")
        #expect(clamped == false)
    }

    /// Regression: the build path read the limit with `Int64(...) ?? 2`, so a
    /// fractional request could not be parsed and silently became 2 - four times
    /// what a service asking for 0.5 wanted, with no message. The run path failed
    /// loudly instead, which is how this was noticed at all.
    /// An earlier version of this test called clampCPULimit and asserted on its
    /// result, which passes whether or not the build path uses it - confirmed by
    /// mutation: reverting that line to `Int64(...) ?? 2` left the test green.
    /// It now goes through the build path's own function.
    @Test("a fractional limit does not become the fallback on the build path")
    func fractionalDoesNotBecomeFallback() throws {
        let svc = try YAMLDecoder().decode(Service.self, from: """
        image: alpine
        deploy:
          resources:
            limits:
              cpus: "0.5"
        """)
        let count = ComposeUp.builderCPUCount(for: svc)
        #expect(count == 1)
        #expect(count != 2, "0.5 must not silently become the fallback of 2")
    }

    @Test("a service with no cpu limit gets the builder default")
    func noLimitUsesDefault() throws {
        let svc = try YAMLDecoder().decode(Service.self, from: "image: alpine")
        #expect(ComposeUp.builderCPUCount(for: svc) == 2)
    }

    @Test("a whole cpu limit reaches the builder unchanged")
    func wholeLimitReachesBuilder() throws {
        let svc = try YAMLDecoder().decode(Service.self, from: """
        image: alpine
        deploy:
          resources:
            limits:
              cpus: "4"
        """)
        #expect(ComposeUp.builderCPUCount(for: svc) == 4)
    }
}
