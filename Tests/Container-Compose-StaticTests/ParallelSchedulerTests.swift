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

/// `dependencyLevels` groups services into launch WAVES: every service in
/// wave k has all of its in-set dependencies in an earlier wave, so a whole
/// wave can be `container run` launched concurrently. This is the pure,
/// daemon-free core of the parallel `up` (issue #128).
@Suite("Parallel Scheduler Levels")
struct ParallelSchedulerTests {

    @Test("Linear chain is not parallelized: web -> app -> db")
    func linearChainOrdersByLevel() throws {
        let web = Service(image: "nginx", depends_on: ["app"])
        let app = Service(image: "myapp", depends_on: ["db"])
        let db = Service(image: "postgres", depends_on: nil)

        let levels = try Service.dependencyLevels([("web", web), ("app", app), ("db", db)])

        #expect(levels == [["db"], ["app"], ["web"]])
    }

    @Test("Independent services form a single wave (the #128 case)")
    func independentServicesFormOneWave() throws {
        let a = Service(image: "a", depends_on: nil)
        let b = Service(image: "b", depends_on: nil)
        let c = Service(image: "c", depends_on: nil)

        let levels = try Service.dependencyLevels([("a", a), ("b", b), ("c", c)])

        #expect(levels.count == 1)
        #expect(Set(levels[0]) == ["a", "b", "c"])
    }

    @Test("Diamond graph groups siblings into the same wave")
    func diamondGraphGroupsSiblings() throws {
        // front depends on web+api; web+api both depend on db.
        let front = Service(image: "front", depends_on: ["web", "api"])
        let web = Service(image: "web", depends_on: ["db"])
        let api = Service(image: "api", depends_on: ["db"])
        let db = Service(image: "db", depends_on: nil)

        let levels = try Service.dependencyLevels(
            [("front", front), ("web", web), ("api", api), ("db", db)])

        #expect(levels.count == 3)
        #expect(levels[0] == ["db"])
        #expect(Set(levels[1]) == ["web", "api"])
        #expect(levels[2] == ["front"])
    }

    @Test("A dependency cycle throws instead of deadlocking")
    func cycleThrows() {
        let web = Service(image: "web", depends_on: ["app"])
        let app = Service(image: "app", depends_on: ["web"])

        #expect(throws: (any Error).self) {
            try Service.dependencyLevels([("web", web), ("app", app)])
        }
    }

    @Test("A self-dependency throws")
    func selfDependencyThrows() {
        let a = Service(image: "a", depends_on: ["a"])

        #expect(throws: (any Error).self) {
            try Service.dependencyLevels([("a", a)])
        }
    }

    @Test("depends_on naming a service outside the set is ignored")
    func dependsOnAbsentServiceIsIgnored() throws {
        // `web` depends on `db`, but `db` is not in the selected set
        // (e.g. excluded by a profile). It must not hang or throw — `web`
        // is treated as having no in-set dependency, so it lands in wave 0.
        let web = Service(image: "nginx", depends_on: ["db"])

        let levels = try Service.dependencyLevels([("web", web)])

        #expect(levels == [["web"]])
    }
}
