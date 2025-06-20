//
//  ResourceReservations.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// **FIXED**: Renamed from `ResourceReservables` to `ResourceReservations` and made `Codable`.
/// CPU and memory reservations.
struct ResourceReservations: Codable, Hashable {
    /// CPU reservation (e.g., "0.25")
    let cpus: String?
    /// Memory reservation (e.g., "256M")
    let memory: String?
    /// Device reservations for GPUs or other devices
    let devices: [DeviceReservation]?
}
