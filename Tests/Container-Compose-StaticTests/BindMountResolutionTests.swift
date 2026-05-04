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

/// Coverage for bind-mount source path normalization (issue #4). Apple
/// `container` rejects relative paths in `-v` because its volume-name
/// validation regex `^[A-Za-z0-9][A-Za-z0-9_.-]*$` doesn't match strings
/// starting with `./`, `../`, or containing `/`. Our helper resolves the
/// source against the project's working directory and collapses `.` / `..`
/// segments before the path goes into the run args.
@Suite("Bind Mount Source Resolution")
struct BindMountResolutionTests {

    @Test("./foo resolves to <cwd>/foo")
    func dotSlashRelative() {
        let result = ComposeUp.resolveBindMountSource("./foo", cwd: "/work/proj")
        #expect(result == "/work/proj/foo")
    }

    @Test("bare relative path foo/bar resolves under <cwd>")
    func bareRelative() {
        let result = ComposeUp.resolveBindMountSource("foo/bar", cwd: "/work/proj")
        #expect(result == "/work/proj/foo/bar")
    }

    @Test("../foo resolves to <parent>/foo")
    func parentRelative() {
        let result = ComposeUp.resolveBindMountSource("../shared", cwd: "/work/proj")
        #expect(result == "/work/shared")
    }

    @Test("intermediate .. collapses (foo/../bar)")
    func intermediateDotDot() {
        let result = ComposeUp.resolveBindMountSource("foo/../bar", cwd: "/work/proj")
        #expect(result == "/work/proj/bar")
    }

    @Test("absolute path /abs/foo passes through unchanged")
    func absolutePath() {
        let result = ComposeUp.resolveBindMountSource("/var/lib/data", cwd: "/work/proj")
        #expect(result == "/var/lib/data")
    }

    @Test("absolute path with intermediate /./ does NOT get rewritten (already absolute)")
    func absoluteUnchanged() {
        // Behavior choice: an already-absolute path is passed through verbatim.
        // The user wrote what they meant; we don't second-guess.
        let result = ComposeUp.resolveBindMountSource("/foo/./bar", cwd: "/work/proj")
        #expect(result == "/foo/./bar")
    }

    @Test("~/foo passes through unchanged (left to apple/container to expand)")
    func tildePath() {
        // FileManager doesn't expand `~` and apple/container does. Preserve
        // the literal so the daemon receives the user's exact intent.
        let result = ComposeUp.resolveBindMountSource("~/data", cwd: "/work/proj")
        #expect(result == "~/data")
    }

    @Test(".//foo collapses double slash")
    func doubleSlashCollapses() {
        let result = ComposeUp.resolveBindMountSource(".//foo", cwd: "/work/proj")
        #expect(result == "/work/proj/foo")
    }

    @Test("the issue #4 case: ./app → <cwd>/app (matches the regex container expects)")
    func issue4Case() {
        let result = ComposeUp.resolveBindMountSource("./app", cwd: "/Users/adrum/Developer/test")
        #expect(result == "/Users/adrum/Developer/test/app")
        // The post-condition that matters: result starts with `/` and contains
        // no `./` or `..` segments — matches what container will accept.
        #expect(result.hasPrefix("/"))
        #expect(!result.contains("/./"))
        #expect(!result.contains("/.."))
    }
}
