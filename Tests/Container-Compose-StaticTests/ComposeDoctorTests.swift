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
//===----------------------------------------------------------------------===//

import ArgumentParser
import Testing
@testable import ContainerComposeCore

struct ComposeDoctorTests {
    @Test func acceptsPinnedRelease() throws {
        let version = try ComposeDoctor.checkVersion("container CLI version 1.7.1 (build: release, commit: abc1234)")
        #expect(version == "1.7.1")
    }

    @Test(arguments: [
        "container CLI version 1.7.0",
        "container CLI version 1.7.2",
        "container CLI version 1.7.1-rc.1",
        "unexpected output",
    ])
    func rejectsUnverifiedVersions(_ response: String) {
        #expect(throws: ValidationError.self) {
            try ComposeDoctor.checkVersion(response)
        }
    }
}
