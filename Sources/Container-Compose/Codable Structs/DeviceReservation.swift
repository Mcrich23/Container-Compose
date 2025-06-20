//
//  DeviceReservation.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Device reservations for GPUs or other devices.
struct DeviceReservation: Codable, Hashable {
    /// Device capabilities
    let capabilities: [String]?
    /// Device driver
    let driver: String?
    /// Number of devices
    let count: String?
    /// Specific device IDs
    let device_ids: [String]?
}
