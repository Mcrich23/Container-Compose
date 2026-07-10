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
import ContainerCommands
import ContainerAPIClient
import TestHelpers
@testable import ContainerComposeCore

/// Tests for the DNS-aware path in `ComposeUp`. These require a DNS domain to be
/// pre-registered with `sudo container system dns create <domain>`. The test
/// uses `dnstest` as a conventional fixed domain name; if it isn't registered,
/// the test logs an instruction and returns rather than failing.
@Suite("Compose Up Tests - Real DNS path", .containerDependent, .serialized)
struct ComposeUpDnsTests {

    private static let testDomain = "dnstest"

    func stopInstance(location: URL) async throws {
        var composeDown = try ComposeDown.parse(["--cwd", location.path(percentEncoded: false)])
        try await composeDown.run()
    }

    /// Mirrors `ComposeUp.checkDnsDomainRegistered` without making it public —
    /// shells out and parses with the same helper used by the production code.
    private func dnsDomainRegistered(_ domain: String) -> Bool {
        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = ["container", "system", "dns", "list"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return false }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return ComposeUp.dnsListContainsDomain(text, domain: domain)
    }

    /// Run `container exec` and return stdout. Returns nil on failure.
    private func containerExec(_ id: String, _ args: [String]) -> String? {
        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = ["container", "exec", id] + args
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    @Test("With DNS available, services use dotted names and skip /etc/hosts patching")
    func dnsPathUsesDottedNamesAndSkipsHostsPatch() async throws {
        guard dnsDomainRegistered(Self.testDomain) else {
            print("""
            Skipping: requires '\(Self.testDomain)' to be registered.
            Enable with: sudo container system dns create \(Self.testDomain)
            """)
            return
        }

        let yaml = """
        name: \(Self.testDomain)
        services:
          db:
            image: alpine:latest
            command: ["sleep", "120"]
          app:
            image: alpine:latest
            command: ["sleep", "120"]
            depends_on: [db]
        """
        let project = try DockerComposeYamlFiles.copyYamlToTemporaryLocation(yaml: yaml)

        var composeUp = try ComposeUp.parse(["-d", "--cwd", project.base.path(percentEncoded: false)])
        try await composeUp.run()

        let appID = "app.\(Self.testDomain)"
        let dbID = "db.\(Self.testDomain)"

        // Containers must exist under their dotted IDs.
        let client = ContainerClient()
        let appContainer = try? await client.get(id: appID)
        let dbContainer = try? await client.get(id: dbID)
        #expect(appContainer != nil, "expected container '\(appID)' to exist")
        #expect(dbContainer != nil, "expected container '\(dbID)' to exist")

        // /etc/hosts in the app container must NOT contain a cross-patched
        // entry for `db` — DNS path skips `crossPatchHostsForService`.
        let hosts = containerExec(appID, ["cat", "/etc/hosts"]) ?? ""
        #expect(!hosts.contains(" db\n") && !hosts.hasSuffix(" db"),
                "/etc/hosts unexpectedly contains a 'db' entry — cross-patcher should be skipped on DNS path. Contents:\n\(hosts)")

        // resolv.conf inside the container should carry the project's DNS domain.
        let resolv = containerExec(appID, ["cat", "/etc/resolv.conf"]) ?? ""
        #expect(resolv.contains("domain \(Self.testDomain)"),
                "/etc/resolv.conf missing 'domain \(Self.testDomain)':\n\(resolv)")

        // Real DNS resolution: short and dotted names both work.
        let shortLookup = containerExec(appID, ["getent", "hosts", "db"]) ?? ""
        let dottedLookup = containerExec(appID, ["getent", "hosts", dbID]) ?? ""
        #expect(shortLookup.contains(dbID), "short-name 'db' did not resolve to peer (got: \(shortLookup))")
        #expect(dottedLookup.contains(dbID), "dotted name '\(dbID)' did not resolve (got: \(dottedLookup))")

        try? await stopInstance(location: project.base)
        // Best-effort hard cleanup of stopped containers (ComposeDown stops but
        // doesn't remove, matching docker compose down semantics).
        _ = containerExec(appID, [])  // no-op if not running
        let delete = Process()
        delete.launchPath = "/usr/bin/env"
        delete.arguments = ["container", "delete", "-f", appID, dbID]
        delete.standardOutput = Pipe()
        delete.standardError = Pipe()
        try? delete.run()
        delete.waitUntilExit()
    }
}
