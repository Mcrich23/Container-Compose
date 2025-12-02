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

@Suite("Service Dependency Resolution Tests")
struct ServiceDependencyTests {
    
    @Test("Simple dependency chain - web depends on db")
    func simpleDependencyChain() throws {
        let web = Service(image: "nginx", depends_on: ["db": DependencyConfig(condition: .service_started)])
        let db = Service(image: "postgres", depends_on: nil)

        let services: [(String, Service)] = [("web", web), ("db", db)]
        let sorted = try Service.topoSortConfiguredServices(services)

        // db should come before web
        #expect(sorted.count == 2)
        #expect(sorted[0].serviceName == "db")
        #expect(sorted[1].serviceName == "web")
    }
    
    @Test("Multiple dependencies - app depends on db and redis")
    func multipleDependencies() throws {
        let app = Service(image: "myapp", depends_on: [
            "db": DependencyConfig(condition: .service_started),
            "redis": DependencyConfig(condition: .service_started)
        ])
        let db = Service(image: "postgres", depends_on: nil)
        let redis = Service(image: "redis", depends_on: nil)

        let services: [(String, Service)] = [("app", app), ("db", db), ("redis", redis)]
        let sorted = try Service.topoSortConfiguredServices(services)

        #expect(sorted.count == 3)
        // app should be last
        #expect(sorted[2].serviceName == "app")
        // db and redis should come before app
        let firstTwo = Set([sorted[0].serviceName, sorted[1].serviceName])
        #expect(firstTwo.contains("db"))
        #expect(firstTwo.contains("redis"))
    }
    
    @Test("Complex dependency chain - web -> app -> db")
    func complexDependencyChain() throws {
        let web = Service(image: "nginx", depends_on: ["app": DependencyConfig(condition: .service_started)])
        let app = Service(image: "myapp", depends_on: ["db": DependencyConfig(condition: .service_started)])
        let db = Service(image: "postgres", depends_on: nil)

        let services: [(String, Service)] = [("web", web), ("app", app), ("db", db)]
        let sorted = try Service.topoSortConfiguredServices(services)

        #expect(sorted.count == 3)
        #expect(sorted[0].serviceName == "db")
        #expect(sorted[1].serviceName == "app")
        #expect(sorted[2].serviceName == "web")
    }
    
    @Test("No dependencies - services should maintain order")
    func noDependencies() throws {
        let web = Service(image: "nginx", depends_on: nil)
        let app = Service(image: "myapp", depends_on: nil)
        let db = Service(image: "postgres", depends_on: nil)
        
        let services: [(String, Service)] = [("web", web), ("app", app), ("db", db)]
        let sorted = try Service.topoSortConfiguredServices(services)
        
        #expect(sorted.count == 3)
    }
    
    @Test("Cyclic dependency should throw error")
    func cyclicDependency() throws {
        let web = Service(image: "nginx", depends_on: ["app": DependencyConfig(condition: .service_started)])
        let app = Service(image: "myapp", depends_on: ["web": DependencyConfig(condition: .service_started)])

        let services: [(String, Service)] = [("web", web), ("app", app)]

        #expect(throws: Error.self) {
            try Service.topoSortConfiguredServices(services)
        }
    }
    
    @Test("Diamond dependency - web and api both depend on db")
    func diamondDependency() throws {
        let web = Service(image: "nginx", depends_on: ["db": DependencyConfig(condition: .service_started)])
        let api = Service(image: "api", depends_on: ["db": DependencyConfig(condition: .service_started)])
        let db = Service(image: "postgres", depends_on: nil)

        let services: [(String, Service)] = [("web", web), ("api", api), ("db", db)]
        let sorted = try Service.topoSortConfiguredServices(services)

        #expect(sorted.count == 3)
        // db should be first
        #expect(sorted[0].serviceName == "db")
        // web and api can be in any order after db
        let lastTwo = Set([sorted[1].serviceName, sorted[2].serviceName])
        #expect(lastTwo.contains("web"))
        #expect(lastTwo.contains("api"))
    }

    @Test("Single service with no dependencies")
    func singleService() throws {
        let web = Service(image: "nginx", depends_on: nil)

        let services: [(String, Service)] = [("web", web)]
        let sorted = try Service.topoSortConfiguredServices(services)

        #expect(sorted.count == 1)
        #expect(sorted[0].serviceName == "web")
    }

    @Test("Service depends on non-existent service - should not crash")
    func dependsOnNonExistentService() throws {
        let web = Service(image: "nginx", depends_on: ["nonexistent": DependencyConfig(condition: .service_started)])

        let services: [(String, Service)] = [("web", web)]
        let sorted = try Service.topoSortConfiguredServices(services)

        // Should complete without crashing
        #expect(sorted.count == 1)
    }

    // MARK: - New Tests for Dependency Conditions

    @Test("Service with service_healthy condition")
    func serviceHealthyCondition() throws {
        let web = Service(image: "nginx", depends_on: [
            "db": DependencyConfig(condition: .service_healthy)
        ])
        let db = Service(image: "postgres", depends_on: nil)

        let services: [(String, Service)] = [("web", web), ("db", db)]
        let sorted = try Service.topoSortConfiguredServices(services)

        #expect(sorted.count == 2)
        #expect(sorted[0].serviceName == "db")
        #expect(sorted[1].serviceName == "web")

        // Verify condition is preserved
        #expect(web.depends_on?["db"]?.condition == .service_healthy)
    }

    @Test("Service with service_completed_successfully condition")
    func serviceCompletedCondition() throws {
        let app = Service(image: "app", depends_on: [
            "migration": DependencyConfig(condition: .service_completed_successfully)
        ])
        let migration = Service(image: "migration", depends_on: nil)

        let services: [(String, Service)] = [("app", app), ("migration", migration)]
        let sorted = try Service.topoSortConfiguredServices(services)

        #expect(sorted.count == 2)
        #expect(sorted[0].serviceName == "migration")
        #expect(sorted[1].serviceName == "app")

        // Verify condition is preserved
        #expect(app.depends_on?["migration"]?.condition == .service_completed_successfully)
    }

    @Test("Mixed dependency conditions")
    func mixedDependencyConditions() throws {
        let web = Service(image: "nginx", depends_on: [
            "app": DependencyConfig(condition: .service_started),
            "db": DependencyConfig(condition: .service_healthy)
        ])
        let app = Service(image: "app", depends_on: nil)
        let db = Service(image: "postgres", depends_on: nil)

        let services: [(String, Service)] = [("web", web), ("app", app), ("db", db)]
        let sorted = try Service.topoSortConfiguredServices(services)

        #expect(sorted.count == 3)
        #expect(sorted[2].serviceName == "web")

        // Verify conditions are preserved
        #expect(web.depends_on?["app"]?.condition == .service_started)
        #expect(web.depends_on?["db"]?.condition == .service_healthy)
    }

    @Test("Dependency with restart and required flags")
    func dependencyWithAdditionalFlags() throws {
        let web = Service(image: "nginx", depends_on: [
            "db": DependencyConfig(
                condition: .service_healthy,
                restart: true,
                required: false
            )
        ])
        let db = Service(image: "postgres", depends_on: nil)

        let services: [(String, Service)] = [("web", web), ("db", db)]
        let sorted = try Service.topoSortConfiguredServices(services)

        #expect(sorted.count == 2)

        // Verify all fields are preserved
        let dbDep = web.depends_on?["db"]
        #expect(dbDep?.condition == .service_healthy)
        #expect(dbDep?.restart == true)
        #expect(dbDep?.required == false)
    }
}

