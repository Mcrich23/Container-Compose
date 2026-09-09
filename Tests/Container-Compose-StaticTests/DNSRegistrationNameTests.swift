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

/// A container reaching `.running` does not mean its name resolves yet — Apple
/// Container publishes the DNS record a moment afterwards, where Docker's
/// embedded DNS updates as the container joins the network. `up` therefore waits
/// for the record before releasing the wave, and this is the name it waits on.
@Suite("DNS Registration Name")
struct DNSRegistrationNameTests {

    @Test("the domain is appended to a plain container name")
    func plainNameGetsDomain() {
        #expect(
            ComposeUp.dnsRegistrationName(containerName: "patroni2", dnsDomain: "dcf")
                == "patroni2.dcf")
    }

    /// Without `container_name`, `up` already builds a dotted name itself;
    /// appending again would wait on `patroni2.dcf.dcf`, which never resolves.
    @Test("an already-qualified name is left alone")
    func qualifiedNameUnchanged() {
        #expect(
            ComposeUp.dnsRegistrationName(containerName: "patroni2.dcf", dnsDomain: "dcf")
                == "patroni2.dcf")
    }

    @Test("a name ending in the domain's letters but not the domain is still qualified")
    func similarSuffixStillQualified() {
        #expect(
            ComposeUp.dnsRegistrationName(containerName: "mydcf", dnsDomain: "dcf")
                == "mydcf.dcf")
    }

    @Test("a multi-label domain works the same way")
    func multiLabelDomain() {
        #expect(
            ComposeUp.dnsRegistrationName(containerName: "db", dnsDomain: "test.local")
                == "db.test.local")
    }
}
