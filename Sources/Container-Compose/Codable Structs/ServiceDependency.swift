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

/// Service-level `depends_on` options for Compose map-form dependencies.
public struct ServiceDependency: Codable, Hashable {
    public static let serviceStarted = "service_started"
    public static let serviceHealthy = "service_healthy"
    public static let serviceCompletedSuccessfully = "service_completed_successfully"

    /// Dependency condition, for example `service_started` or `service_healthy`.
    public let condition: String?

    /// Compose optional restart hint for dependency updates.
    public let restart: Bool?

    /// Compose optional required hint. Defaults to true in Docker Compose.
    public let required: Bool?

    public var effectiveCondition: String {
        condition ?? Self.serviceStarted
    }

    public init(
        condition: String? = nil,
        restart: Bool? = nil,
        required: Bool? = nil
    ) {
        self.condition = condition
        self.restart = restart
        self.required = required
    }
}
