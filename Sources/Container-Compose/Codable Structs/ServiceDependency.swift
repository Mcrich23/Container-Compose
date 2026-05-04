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

/// Service dependency options from Docker Compose long-form `depends_on`.
public struct ServiceDependency: Codable, Hashable {
    /// Readiness condition such as `service_started`, `service_healthy`, or `service_completed_successfully`.
    public let condition: String?

    /// Whether a dependency failure should fail the dependent service.
    public let required: Bool?

    /// Whether explicit dependency restarts should also restart this service.
    public let restart: Bool?

    public init(condition: String? = nil, required: Bool? = nil, restart: Bool? = nil) {
        self.condition = condition
        self.required = required
        self.restart = restart
    }
}
