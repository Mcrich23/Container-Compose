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

@Suite("Plugin invocation naming")
struct PluginInvocationNamingTests {
    @Test("Standalone invocation keeps the container-compose name")
    func standaloneInvocation() {
        #expect(Main.displayCommandName(forInvocation: "/opt/homebrew/bin/container-compose") == "container-compose")
        #expect(Main.displayCommandName(forInvocation: "container-compose") == "container-compose")
        #expect(Main.displayCommandName(forInvocation: ".build/debug/container-compose") == "container-compose")
    }

    @Test("Plugin invocation renders as `container compose`")
    func pluginInvocation() {
        let pluginPath = "/opt/homebrew/Cellar/container/0.12.3/libexec/container-plugins/compose/bin/compose"
        #expect(Main.displayCommandName(forInvocation: pluginPath) == "container compose")
        #expect(Main.displayCommandName(forInvocation: "compose") == "container compose")
    }

    @Test("Missing or unrecognized invocation falls back to the standalone name")
    func unknownInvocation() {
        #expect(Main.displayCommandName(forInvocation: nil) == "container-compose")
        #expect(Main.displayCommandName(forInvocation: "/usr/bin/something-else") == "container-compose")
    }
}
