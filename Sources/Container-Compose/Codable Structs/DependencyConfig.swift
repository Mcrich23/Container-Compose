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

//
//  DependencyConfig.swift
//  Container-Compose
//
//  Represents dependency configuration for depends_on with conditions
//

/// Condition types for service dependencies
public enum DependsOnCondition: String, Codable, Hashable {
    case service_started
    case service_healthy
    case service_completed_successfully
}

/// Configuration for a service dependency
public struct DependencyConfig: Codable, Hashable {
    /// Condition that must be met before dependent service starts
    public let condition: DependsOnCondition
    /// Whether to restart the dependent service if this service restarts
    public let restart: Bool?
    /// Whether this dependency is required
    public let required: Bool?

    public init(
        condition: DependsOnCondition = .service_started,
        restart: Bool? = nil,
        required: Bool? = nil
    ) {
        self.condition = condition
        self.restart = restart
        self.required = required
    }
}
