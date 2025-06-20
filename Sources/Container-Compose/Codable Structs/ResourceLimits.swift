//
//  ResourceLimits.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// CPU and memory limits.
struct ResourceLimits: Codable, Hashable {
    /// CPU limit (e.g., "0.5")
    let cpus: String?
    /// Memory limit (e.g., "512M")
    let memory: String?
}
