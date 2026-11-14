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

@Suite("Effective pull platform Tests")
struct EffectivePullPlatformTests {

    @Test("Explicit service platform wins")
    func platformExplicit() {
        let service = Service(image: "nginx", platform: "linux/amd64")
        #expect(service.effectivePullPlatform(environment: [:]) == "linux/amd64")
    }

    @Test("CONTAINER_DEFAULT_PLATFORM defers to container's own resolution")
    func platformEnvDefers() {
        let service = Service(image: "nginx")
        #expect(service.effectivePullPlatform(environment: ["CONTAINER_DEFAULT_PLATFORM": "linux/amd64"]) == nil)
    }

    @Test("Default is the host platform, not the full multi-arch index")
    func platformHostDefault() {
        let service = Service(image: "nginx")
        #expect(service.effectivePullPlatform(environment: [:]) == "linux/arm64")
    }
}
