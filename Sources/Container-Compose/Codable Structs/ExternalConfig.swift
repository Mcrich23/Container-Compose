//
//  ExternalConfig.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Represents an external config reference.
struct ExternalConfig: Codable {
    /// True if the config is external
    let isExternal: Bool
    /// Optional name of the external config if different from key
    let name: String?
}
