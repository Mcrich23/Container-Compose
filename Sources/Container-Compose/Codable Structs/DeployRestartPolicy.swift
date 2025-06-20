//
//  DeployRestartPolicy.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Restart policy for deployed tasks.
struct DeployRestartPolicy: Codable, Hashable {
    /// Condition to restart on (e.g., 'on-failure', 'any')
    let condition: String?
    /// Delay before attempting restart
    let delay: String?
    /// Maximum number of restart attempts
    let max_attempts: Int?
    /// Window to evaluate restart policy
    let window: String?
}
