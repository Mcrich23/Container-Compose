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

@Suite("Requested service validation")
struct RequestedServiceValidationTests {

    private func defined(_ names: String...) -> [(serviceName: String, service: Service)] {
        names.map { ($0, Service(image: "alpine")) }
    }

    @Test("passes when every requested service exists")
    func passesWhenAllExist() throws {
        try Service.validateRequestedServices(["web", "db"], against: defined("web", "db", "cache"))
    }

    @Test("passes when no services are requested")
    func passesWhenNoneRequested() throws {
        try Service.validateRequestedServices([], against: defined("web", "db"))
    }

    @Test("throws for an unknown requested service")
    func throwsForUnknown() {
        #expect(throws: ComposeError.self) {
            try Service.validateRequestedServices(["nope"], against: defined("web", "db"))
        }
    }

    @Test("error message matches docker compose wording and names the service")
    func errorMessageWording() {
        do {
            try Service.validateRequestedServices(["typo"], against: defined("web"))
            Issue.record("expected validateRequestedServices to throw")
        } catch let error as ComposeError {
            #expect(error.errorDescription == "no such service: typo")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("reports the first unknown service when several are requested")
    func reportsFirstUnknown() {
        do {
            try Service.validateRequestedServices(["web", "ghost"], against: defined("web"))
            Issue.record("expected validateRequestedServices to throw")
        } catch let error as ComposeError {
            #expect(error.errorDescription == "no such service: ghost")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
