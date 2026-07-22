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
@testable import ContainerComposeCore

@Suite("DNS Domain Helpers")
struct DnsDomainTests {

    @Test("sanitize - already valid label is unchanged")
    func sanitizeIdentity() {
        #expect(ComposeProject.sanitizeDnsDomain("dnstest") == "dnstest")
        #expect(ComposeProject.sanitizeDnsDomain("my-app-1") == "my-app-1")
    }

    @Test("sanitize - lowercases mixed case")
    func sanitizeLowercases() {
        #expect(ComposeProject.sanitizeDnsDomain("Container-Compose") == "container-compose")
    }

    @Test("sanitize - replaces underscores, dots, spaces with hyphens")
    func sanitizeReplacesSeparators() {
        #expect(ComposeProject.sanitizeDnsDomain("my_app") == "my-app")
        #expect(ComposeProject.sanitizeDnsDomain("my.app") == "my-app")
        #expect(ComposeProject.sanitizeDnsDomain("my app") == "my-app")
    }

    @Test("sanitize - collapses runs of separators")
    func sanitizeCollapsesRuns() {
        #expect(ComposeProject.sanitizeDnsDomain("a__b..c   d") == "a-b-c-d")
    }

    @Test("sanitize - trims leading and trailing hyphens")
    func sanitizeTrims() {
        #expect(ComposeProject.sanitizeDnsDomain("--foo--") == "foo")
        #expect(ComposeProject.sanitizeDnsDomain(".devcontainers") == "devcontainers")
    }

    @Test("sanitize - returns nil for unusable input")
    func sanitizeReturnsNil() {
        #expect(ComposeProject.sanitizeDnsDomain("") == nil)
        #expect(ComposeProject.sanitizeDnsDomain("___") == nil)
        #expect(ComposeProject.sanitizeDnsDomain("...") == nil)
    }

    @Test("sanitize - clamps to 63 chars and re-trims")
    func sanitizeClampsLength() {
        let long = String(repeating: "a", count: 70) + "-"
        let out = ComposeProject.sanitizeDnsDomain(long)
        #expect(out?.count == 63)
        #expect(out?.last != "-")
    }

    @Test("dns list - empty output means not registered")
    func dnsListEmpty() {
        #expect(ComposeUp.dnsListContainsDomain("", domain: "anything") == false)
    }

    @Test("dns list - header-only output (no domains)")
    func dnsListHeaderOnly() {
        #expect(ComposeUp.dnsListContainsDomain("DOMAIN\n", domain: "anything") == false)
    }

    @Test("dns list - matches a registered domain")
    func dnsListMatches() {
        let output = "DOMAIN\ndnstest\nfoo\n"
        #expect(ComposeUp.dnsListContainsDomain(output, domain: "dnstest") == true)
        #expect(ComposeUp.dnsListContainsDomain(output, domain: "foo") == true)
        #expect(ComposeUp.dnsListContainsDomain(output, domain: "bar") == false)
    }

    @Test("dns list - exact match only (no substring)")
    func dnsListExactMatch() {
        let output = "DOMAIN\ndnstest\n"
        #expect(ComposeUp.dnsListContainsDomain(output, domain: "test") == false)
        #expect(ComposeUp.dnsListContainsDomain(output, domain: "dns") == false)
    }
}
