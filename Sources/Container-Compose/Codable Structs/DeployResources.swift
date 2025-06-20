//
//  DeployResources.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Resource constraints for deployment.
struct DeployResources: Codable, Hashable {
    /// Hard limits on resources
    let limits: ResourceLimits?
    /// Guarantees for resources
    let reservations: ResourceReservations?
}
