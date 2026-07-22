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

// .serialized: two tests below mutate the global COMPOSE_PROFILES process
// environment variable via setenv/unsetenv. Swift Testing parallelizes tests
// within a suite by default, so without this trait those tests can race each
// other (or any future test reading COMPOSE_PROFILES), causing intermittent
// failures.
@Suite("Compose profiles support", .serialized)
struct ProfilesTests {

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

    // MARK: - Decoding

    @Test("profiles list form parses")
    func profilesListParses() throws {
        let svc = try decodeService("""
          image: alpine
          profiles:
            - debug
            - frontend
        """)
        #expect(svc.profiles == ["debug", "frontend"])
    }

    @Test("profiles absent when not set")
    func profilesAbsentWhenNotSet() throws {
        let svc = try decodeService("""
          image: alpine
        """)
        #expect(svc.profiles == nil)
    }

    // MARK: - isProfileEligible

    @Test("service with no profiles is always eligible")
    func noProfilesAlwaysEligible() {
        let svc = Service(image: "alpine", profiles: nil)
        #expect(svc.isProfileEligible(activeProfiles: []))
        #expect(svc.isProfileEligible(activeProfiles: ["debug"]))
    }

    @Test("service with empty profiles list is always eligible")
    func emptyProfilesAlwaysEligible() {
        let svc = Service(image: "alpine", profiles: [])
        #expect(svc.isProfileEligible(activeProfiles: []))
    }

    @Test("profiled service is ineligible when its profile is not active")
    func profiledServiceIneligibleWhenInactive() {
        let svc = Service(image: "alpine", profiles: ["debug"])
        #expect(!svc.isProfileEligible(activeProfiles: []))
        #expect(!svc.isProfileEligible(activeProfiles: ["frontend"]))
    }

    @Test("profiled service is eligible when one of its profiles is active")
    func profiledServiceEligibleWhenActive() {
        let svc = Service(image: "alpine", profiles: ["debug", "frontend"])
        #expect(svc.isProfileEligible(activeProfiles: ["frontend"]))
    }

    // MARK: - Service.selectServices — default (no requested services)

    @Test("default selection excludes profiled services when no profile is active")
    func defaultSelectionExcludesProfiledServices() throws {
        let web = Service(image: "nginx", profiles: nil)
        let debugTools = Service(image: "busybox", profiles: ["debug"])
        let services: [(serviceName: String, service: Service)] = [
            ("web", web),
            ("debug-tools", debugTools),
        ]

        let selected = Service.selectServices(from: services, requestedServices: [])

        #expect(selected.map(\.serviceName) == ["web"])
    }

    @Test("default selection includes profiled services when their profile is active")
    func defaultSelectionIncludesActiveProfiledServices() throws {
        let web = Service(image: "nginx", profiles: nil)
        let debugTools = Service(image: "busybox", profiles: ["debug"])
        let services: [(serviceName: String, service: Service)] = [
            ("web", web),
            ("debug-tools", debugTools),
        ]

        let selected = Service.selectServices(from: services, requestedServices: [], activeProfiles: ["debug"])

        #expect(Set(selected.map(\.serviceName)) == ["web", "debug-tools"])
    }

    // MARK: - Service.selectServices — explicit request bypasses the gate

    @Test("explicitly requested service starts even if its profile is inactive")
    func explicitRequestBypassesProfileGate() throws {
        let debugTools = Service(image: "busybox", profiles: ["debug"])
        let services: [(serviceName: String, service: Service)] = [
            ("debug-tools", debugTools),
        ]

        let selected = Service.selectServices(from: services, requestedServices: ["debug-tools"], activeProfiles: [])

        #expect(selected.map(\.serviceName) == ["debug-tools"])
    }

    // MARK: - Service.selectServices — dependency bypasses the gate

    @Test("dependency of an eligible service starts even if its own profile is inactive")
    func dependencyBypassesProfileGate() throws {
        let db = Service(image: "postgres", profiles: ["debug"])
        let api = Service(image: "myapi", depends_on: ["db"], profiles: nil)
        let services: [(serviceName: String, service: Service)] = [
            ("db", db),
            ("api", api),
        ]

        let selected = Service.selectServices(from: services, requestedServices: [], activeProfiles: [])

        #expect(Set(selected.map(\.serviceName)) == ["db", "api"])
    }

    // MARK: - CLI parsing

    @Test("ComposeUp command accepts repeated --profile flags")
    func composeUpCommandAcceptsRepeatedProfileFlags() throws {
        let cmd = try ComposeUp.parse(["--profile", "debug", "--profile", "frontend"])
        #expect(cmd.projectOptions.composeFileOptions.profile == ["debug", "frontend"])
    }

    @Test("ComposeUp command defaults profile to empty")
    func composeUpCommandDefaultsProfileToEmpty() throws {
        let cmd = try ComposeUp.parse([])
        #expect(cmd.projectOptions.composeFileOptions.profile.isEmpty)
    }

    @Test("ComposeBuild command accepts --profile flag")
    func composeBuildCommandAcceptsProfileFlag() throws {
        let cmd = try ComposeBuild.parse(["--profile", "debug"])
        #expect(cmd.projectOptions.composeFileOptions.profile == ["debug"])
    }

    @Test("ComposeDown command accepts --profile flag")
    func composeDownCommandAcceptsProfileFlag() throws {
        let cmd = try ComposeDown.parse(["--profile", "debug"])
        #expect(cmd.projectOptions.composeFileOptions.profile == ["debug"])
    }

    // MARK: - COMPOSE_PROFILES environment variable

    @Test("activeProfiles merges --profile flags with COMPOSE_PROFILES env var")
    func activeProfilesMergesEnvVar() throws {
        setenv("COMPOSE_PROFILES", "backend, debug", 1)
        defer { unsetenv("COMPOSE_PROFILES") }

        let cmd = try ComposeUp.parse(["--profile", "frontend"])
        #expect(cmd.projectOptions.composeFileOptions.activeProfiles == ["frontend", "backend", "debug"])
    }

    @Test("activeProfiles is empty when neither --profile nor COMPOSE_PROFILES is set")
    func activeProfilesEmptyWhenUnset() throws {
        unsetenv("COMPOSE_PROFILES")

        let cmd = try ComposeUp.parse([])
        #expect(cmd.projectOptions.composeFileOptions.activeProfiles.isEmpty)
    }
}
