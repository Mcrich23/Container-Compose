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

@Suite("Entrypoint + Command Translation")
struct EntrypointCommandTests {

    @Test("nil entrypoint and nil command → no flag, no positional args")
    func bothNil() {
        let r = ComposeUp.entrypointAndCommandArgs(entrypoint: nil, command: nil)
        #expect(r.entrypointFlag == nil)
        #expect(r.positional == [])
    }

    @Test("command only → no flag, command as positional")
    func commandOnly() {
        let r = ComposeUp.entrypointAndCommandArgs(
            entrypoint: nil,
            command: ["nginx", "-g", "daemon off;"]
        )
        #expect(r.entrypointFlag == nil)
        #expect(r.positional == ["nginx", "-g", "daemon off;"])
    }

    @Test("single-element entrypoint, no command → flag set, no positional")
    func singleEntrypointNoCommand() {
        let r = ComposeUp.entrypointAndCommandArgs(
            entrypoint: ["/usr/local/bin/start.sh"],
            command: nil
        )
        #expect(r.entrypointFlag == "/usr/local/bin/start.sh")
        #expect(r.positional == [])
    }

    @Test("multi-element entrypoint, no command → first goes to flag, rest positional")
    func multiEntrypointNoCommand() {
        let r = ComposeUp.entrypointAndCommandArgs(
            entrypoint: ["/bin/sh", "-c", "echo hi"],
            command: nil
        )
        #expect(r.entrypointFlag == "/bin/sh")
        #expect(r.positional == ["-c", "echo hi"])
    }

    @Test("entrypoint AND command both set → combined (regression for issue #77)")
    func bothEntrypointAndCommand() {
        let r = ComposeUp.entrypointAndCommandArgs(
            entrypoint: ["/bin/sh", "-c"],
            command: ["echo hello && echo world"]
        )
        #expect(r.entrypointFlag == "/bin/sh")
        #expect(r.positional == ["-c", "echo hello && echo world"])
    }

    @Test("issue #77: bash -c + multi-line heredoc command")
    func issue77HeredocCase() {
        // YAML this models:
        //   entrypoint: ["/bin/bash", "-c"]
        //   command:
        //     - |
        //       sed -i "s|Listen 80|Listen 8080|" /etc/httpd.conf
        //       exec httpd-foreground
        let heredoc = """
        sed -i "s|Listen 80|Listen 8080|" /etc/httpd.conf
        exec httpd-foreground

        """
        let r = ComposeUp.entrypointAndCommandArgs(
            entrypoint: ["/bin/bash", "-c"],
            command: [heredoc]
        )
        #expect(r.entrypointFlag == "/bin/bash")
        #expect(r.positional.count == 2)
        #expect(r.positional.first == "-c")
        #expect(r.positional.last == heredoc)
    }

    @Test("empty entrypoint array → treated as nil")
    func emptyEntrypoint() {
        let r = ComposeUp.entrypointAndCommandArgs(entrypoint: [], command: ["echo"])
        #expect(r.entrypointFlag == nil)
        #expect(r.positional == ["echo"])
    }

    @Test("empty command array → just empty positional")
    func emptyCommand() {
        let r = ComposeUp.entrypointAndCommandArgs(
            entrypoint: ["/bin/sh"],
            command: []
        )
        #expect(r.entrypointFlag == "/bin/sh")
        #expect(r.positional == [])
    }
}
