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
@testable import Yams
@testable import ContainerComposeCore

/// A one-shot service only passes *through* `.running`. The readiness wait
/// returned on the first `.running` it saw, so a fast init that had not quite
/// exited yet was recorded as running, and every dependent declaring
/// `service_completed_successfully` was refused:
///
///     Service 'etcd2' depends on 'etcd-init' with condition
///     'service_completed_successfully', but 'etcd-init' has not completed
///     successfully.
///
/// Whether a service must be waited out is not readable from the service — it
/// lives on whoever depends on it.
@Suite("Services Required To Complete")
struct RequiredToCompleteTests {

    private func targets(_ yaml: String) throws -> [(serviceName: String, service: Service)] {
        let doc = try YAMLDecoder().decode(DockerCompose.self, from: yaml)
        return doc.services.compactMap { name, service in
            service.map { (serviceName: name, service: $0) }
        }
    }

    @Test("a service depended on for completion is collected")
    func completionDependencyCollected() throws {
        let t = try targets("""
        services:
          init:
            image: alpine
          app:
            image: nginx
            depends_on:
              init:
                condition: service_completed_successfully
        """)
        #expect(Service.servicesRequiredToComplete(t) == ["init"])
    }

    @Test("service_started and service_healthy do not require completion")
    func otherConditionsExcluded() throws {
        let t = try targets("""
        services:
          db:
            image: postgres
          cache:
            image: redis
          app:
            image: nginx
            depends_on:
              db:
                condition: service_healthy
              cache:
                condition: service_started
        """)
        #expect(Service.servicesRequiredToComplete(t).isEmpty)
    }

    /// `depends_on` in list form carries no condition, and the default is
    /// `service_started` — so it must not be collected.
    @Test("the list form of depends_on defaults to service_started")
    func listFormDefaultsToStarted() throws {
        let t = try targets("""
        services:
          db:
            image: postgres
          app:
            image: nginx
            depends_on:
              - db
        """)
        #expect(Service.servicesRequiredToComplete(t).isEmpty)
    }

    /// dcf-local-env's shape: three peers each waiting on the same init.
    @Test("one init depended on by several services is collected once")
    func sharedInitCollectedOnce() throws {
        let t = try targets("""
        services:
          etcd-init:
            image: alpine
          etcd1:
            image: etcd
            depends_on:
              etcd-init:
                condition: service_completed_successfully
          etcd2:
            image: etcd
            depends_on:
              etcd-init:
                condition: service_completed_successfully
          etcd3:
            image: etcd
            depends_on:
              etcd-init:
                condition: service_completed_successfully
        """)
        #expect(Service.servicesRequiredToComplete(t) == ["etcd-init"])
    }

    @Test("a service nobody depends on requires nothing")
    func noDependenciesAtAll() throws {
        let t = try targets("""
        services:
          solo:
            image: nginx
        """)
        #expect(Service.servicesRequiredToComplete(t).isEmpty)
    }

    @Test("two distinct one-shots are both collected")
    func twoOneShots() throws {
        let t = try targets("""
        services:
          a-init:
            image: alpine
          b-init:
            image: alpine
          app:
            image: nginx
            depends_on:
              a-init:
                condition: service_completed_successfully
              b-init:
                condition: service_completed_successfully
        """)
        #expect(Service.servicesRequiredToComplete(t) == ["a-init", "b-init"])
    }
}
