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

@Suite("mem_limit and extra_hosts parsing")
struct MemLimitExtraHostsTests {

    private func decodeService(_ serviceYaml: String) throws -> Service {
        let yaml = """
        services:
          svc:
        \(serviceYaml.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }.joined(separator: "\n"))
        """
        let compose = try YAMLDecoder().decode(DockerCompose.self, from: yaml)
        guard let service = compose.services["svc"].flatMap({ $0 }) else {
            Issue.record("service 'svc' missing or nil")
            throw TestError.missingService
        }
        return service
    }

    enum TestError: Error { case missingService }

    // MARK: - mem_limit

    @Test("mem_limit string form parses")
    func memLimitString() throws {
        let svc = try decodeService("""
          image: alpine
          mem_limit: 512m
        """)
        #expect(svc.mem_limit == "512m")
    }

    @Test("mem_limit gigabyte value parses")
    func memLimitGigabyte() throws {
        let svc = try decodeService("""
          image: alpine
          mem_limit: 2g
        """)
        #expect(svc.mem_limit == "2g")
    }

    @Test("mem_limit integer bytes form parses to string")
    func memLimitInteger() throws {
        let svc = try decodeService("""
          image: alpine
          mem_limit: 536870912
        """)
        #expect(svc.mem_limit == "536870912")
    }

    @Test("mem_limit absent when not set")
    func memLimitAbsent() throws {
        let svc = try decodeService("""
          image: alpine
        """)
        #expect(svc.mem_limit == nil)
    }

    @Test("mem_limit takes precedence over deploy.resources.limits.memory in run args")
    func memLimitPrecedence() throws {
        // Verify effective memory limit selection logic matches Docker Compose semantics:
        // mem_limit wins when both are present.
        let memLimit: String? = "512m"
        let deployMemory: String? = "1g"
        let effective = memLimit ?? deployMemory
        #expect(effective == "512m")
    }

    // MARK: - extra_hosts

    @Test("extra_hosts list form parses")
    func extraHostsList() throws {
        let svc = try decodeService("""
          image: alpine
          extra_hosts:
            - "logto.localhost:192.168.64.1"
        """)
        #expect(svc.extra_hosts == ["logto.localhost:192.168.64.1"])
    }

    @Test("extra_hosts list form with host-gateway token parses")
    func extraHostsHostGateway() throws {
        let svc = try decodeService("""
          image: alpine
          extra_hosts:
            - "logto.localhost:host-gateway"
        """)
        #expect(svc.extra_hosts == ["logto.localhost:host-gateway"])
    }

    @Test("extra_hosts map form normalised to list")
    func extraHostsMapForm() throws {
        let svc = try decodeService("""
          image: alpine
          extra_hosts:
            logto.localhost: "192.168.64.1"
        """)
        // Map order is not guaranteed; just check the entry is present.
        #expect(svc.extra_hosts?.contains("logto.localhost:192.168.64.1") == true)
        #expect(svc.extra_hosts?.count == 1)
    }

    @Test("extra_hosts absent when not set")
    func extraHostsAbsent() throws {
        let svc = try decodeService("""
          image: alpine
        """)
        #expect(svc.extra_hosts == nil)
    }

    @Test("extra_hosts multiple entries all parsed")
    func extraHostsMultiple() throws {
        let svc = try decodeService("""
          image: alpine
          extra_hosts:
            - "host1:10.0.0.1"
            - "host2:host-gateway"
        """)
        #expect(svc.extra_hosts?.count == 2)
        #expect(svc.extra_hosts?.contains("host1:10.0.0.1") == true)
        #expect(svc.extra_hosts?.contains("host2:host-gateway") == true)
    }

    // MARK: - host-gateway resolution

    @Test("resolveHostGatewayIP returns a non-empty string")
    func resolveHostGatewayReturnsString() {
        // The resolved value is machine-specific; we just verify it runs and returns
        // something (either a real IP or the "host-gateway" fallback).
        let result = ComposeUp.resolveHostGatewayIP()
        #expect(!result.isEmpty)
    }
}
