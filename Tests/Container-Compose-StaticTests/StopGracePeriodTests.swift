//===----------------------------------------------------------------------===//
// Copyright © 2025 Morris Richman and the Container-Compose project authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import ContainerResource
import Testing
import Yams

@testable import ContainerComposeCore

@Suite("Stop Grace Period Tests")
struct StopGracePeriodTests {
    @Test("Parse a combined stop grace period")
    func parseCombinedStopGracePeriod() throws {
        let service = try decodeService("""
            image: alpine:latest
            stop_grace_period: 1m30s
            """)

        #expect(service.stop_grace_period?.timeoutInSeconds == 90)
        #expect(service.stopTimeoutInSeconds == 90)
    }

    @Test("Use Compose's ten-second default when omitted")
    func defaultStopGracePeriod() throws {
        let service = try decodeService("image: alpine:latest")

        #expect(service.stop_grace_period == nil)
        #expect(service.stopTimeoutInSeconds == 10)
    }

    @Test("Truncate subsecond stop grace periods for the runtime")
    func truncateSubsecondStopGracePeriod() throws {
        let service = try decodeService("""
            image: alpine:latest
            stop_grace_period: 1.999s
            """)

        #expect(service.stopTimeoutInSeconds == 1)
    }

    @Test("Reject invalid stop grace periods")
    func rejectInvalidStopGracePeriods() {
        for value in ["1", "-1s", "1d", "1s-invalid", "2147483648s"] {
            #expect(throws: Error.self) {
                try decodeService("""
                    image: alpine:latest
                    stop_grace_period: \(value)
                    """)
            }
        }
    }

    @Test("Build explicit stop options")
    func buildStopOptions() throws {
        let service = try decodeService("""
            image: alpine:latest
            stop_grace_period: 12s
            """)
        let options = ComposeStopOptions.resolve(for: service)

        #expect(options.timeoutInSeconds == 12)
        #expect(options.signal == nil)
    }

    private func decodeService(_ serviceYaml: String) throws -> Service {
        let yaml = """
            services:
              app:
            \(serviceYaml.split(separator: "\n", omittingEmptySubsequences: false).map { "    \($0)" }.joined(separator: "\n"))
            """
        let compose = try YAMLDecoder().decode(DockerCompose.self, from: yaml)
        return try #require(compose.services["app"] ?? nil)
    }
}
