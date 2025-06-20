//
//  ServiceSecret.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Represents a service's usage of a secret.
struct ServiceSecret: Codable, Hashable {
    /// Name of the secret being used
    let source: String

    /// Path in the container where the secret will be mounted
    let target: String?

    /// User ID for the mounted secret file
    let uid: String?

    /// Group ID for the mounted secret file
    let gid: String?

    /// Permissions mode for the mounted secret file
    let mode: Int?

    /// Custom initializer to handle `secret_name` (string) or `{ source: secret_name, target: /path }` (object).
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let sourceName = try? container.decode(String.self) {
            self.source = sourceName
            self.target = nil
            self.uid = nil
            self.gid = nil
            self.mode = nil
        } else {
            let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
            self.source = try keyedContainer.decode(String.self, forKey: .source)
            self.target = try keyedContainer.decodeIfPresent(String.self, forKey: .target)
            self.uid = try keyedContainer.decodeIfPresent(String.self, forKey: .uid)
            self.gid = try keyedContainer.decodeIfPresent(String.self, forKey: .gid)
            self.mode = try keyedContainer.decodeIfPresent(Int.self, forKey: .mode)
        }
    }

    enum CodingKeys: String, CodingKey {
        case source, target, uid, gid, mode
    }
}
