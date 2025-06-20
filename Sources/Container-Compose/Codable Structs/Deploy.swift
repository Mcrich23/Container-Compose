//
//  Deploy.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Represents the `deploy` configuration for a service (primarily for Swarm orchestration).
struct Deploy: Codable, Hashable {
    /// Deployment mode (e.g., 'replicated', 'global')
    let mode: String?
    /// Number of replicated service tasks
    let replicas: Int?
    /// Resource constraints (limits, reservations)
    let resources: DeployResources?
    /// Restart policy for tasks
    let restart_policy: DeployRestartPolicy?
}
