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
//  DeployRestartPolicy.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Restart policy for deployed tasks.
public struct DeployRestartPolicy: Codable, Hashable {
    /// Condition to restart on (e.g., 'on-failure', 'any')
    public let condition: String?
    /// Delay before attempting restart
    public let delay: String?
    /// Maximum number of restart attempts
    public let max_attempts: Int?
    /// Window to evaluate restart policy
    public let window: String?
}
