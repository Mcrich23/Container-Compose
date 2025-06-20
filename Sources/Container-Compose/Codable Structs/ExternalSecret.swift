//
//  ExternalSecret.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Represents an external secret reference.
struct ExternalSecret: Codable {
    /// True if the secret is external
    let isExternal: Bool
    /// Optional name of the external secret if different from key
    let name: String?
}
