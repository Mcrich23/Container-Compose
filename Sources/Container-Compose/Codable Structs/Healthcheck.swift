//
//  Healthcheck.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Healthcheck configuration for a service.
struct Healthcheck: Codable, Hashable {
    /// Command to run to check health
    let test: [String]?
    /// Grace period for the container to start
    let start_period: String?
    /// How often to run the check
    let interval: String?
    /// Number of consecutive failures to consider unhealthy
    let retries: Int?
    /// Timeout for each check
    let timeout: String?
}
