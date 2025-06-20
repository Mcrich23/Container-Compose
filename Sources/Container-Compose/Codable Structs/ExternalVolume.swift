//
//  ExternalVolume.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Represents an external volume reference.
struct ExternalVolume: Codable {
    /// True if the volume is external
    let isExternal: Bool
    /// Optional name of the external volume if different from key
    let name: String?
}
