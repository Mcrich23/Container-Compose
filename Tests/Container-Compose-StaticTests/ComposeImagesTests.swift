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

@Suite("Compose images Tests")
struct ComposeImagesTests {

    // MARK: - splitReference

    @Test("Reference with tag splits on the last colon")
    func splitReferenceWithTag() {
        let (repo, tag) = ComposeImages.splitReference("nginx:alpine")
        #expect(repo == "nginx")
        #expect(tag == "alpine")
    }

    @Test("Reference without tag defaults to latest")
    func splitReferenceNoTag() {
        let (repo, tag) = ComposeImages.splitReference("nginx")
        #expect(repo == "nginx")
        #expect(tag == "latest")
    }

    @Test("Colon in a registry host:port is not treated as a tag separator")
    func splitReferenceRegistryPort() {
        let (repo, tag) = ComposeImages.splitReference("localhost:5000/myapp")
        #expect(repo == "localhost:5000/myapp")
        #expect(tag == "latest")

        let (repo2, tag2) = ComposeImages.splitReference("localhost:5000/myapp:v2")
        #expect(repo2 == "localhost:5000/myapp")
        #expect(tag2 == "v2")
    }

    // MARK: - shortDigest

    @Test("Digest shortens to 12 hex chars without the algorithm prefix")
    func shortDigest() {
        #expect(ComposeImages.shortDigest("sha256:82a1d74c5988deadbeef00112233445566778899aabbccdd") == "82a1d74c5988")
        #expect(ComposeImages.shortDigest("82a1d74c5988deadbeef") == "82a1d74c5988")
    }

    // MARK: - humanReadableSize

    @Test("Sizes render with sensible units")
    func humanReadableSize() {
        #expect(ComposeImages.humanReadableSize(0) == "")
        #expect(ComposeImages.humanReadableSize(512) == "512 B")
        #expect(ComposeImages.humanReadableSize(2048) == "2.0 KB")
        #expect(ComposeImages.humanReadableSize(391 * 1024 * 1024) == "391 MB")
    }

    // MARK: - CLI parsing

    @Test("images accepts service arguments alongside the project option group")
    func imagesParsesArguments() throws {
        let cmd = try ComposeImages.parse(["web"])
        #expect(cmd.services == ["web"])
    }
}
