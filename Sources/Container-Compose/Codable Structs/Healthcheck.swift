//===----------------------------------------------------------------------===//
// Copyright © 2025 Apple Inc. and the container project authors. All rights reserved.
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
//  Healthcheck.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Healthcheck configuration for a service.
public struct Healthcheck: Codable, Hashable {
    /// Command to run to check health
    public let test: [String]?
    /// Grace period for the container to start
    public let start_period: String?
    /// How often to run the check
    public let interval: String?
    /// Number of consecutive failures to consider unhealthy
    public let retries: Int?
    /// Timeout for each check
    public let timeout: String?
    
    public init(
        test: [String]? = nil,
        start_period: String? = nil,
        interval: String? = nil,
        retries: Int? = nil,
        timeout: String? = nil
    ) {
        self.test = test
        self.start_period = start_period
        self.interval = interval
        self.retries = retries
        self.timeout = timeout
    }
}
