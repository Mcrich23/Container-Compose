//
//  Build.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//


/// Represents the `build` configuration for a service.
struct Build: Codable, Hashable {
    /// Path to the build context
    let context: String
    /// Optional path to the Dockerfile within the context
    let dockerfile: String?
    /// Build arguments
    let args: [String: String]?
    
    /// Custom initializer to handle `build: .` (string) or `build: { context: . }` (object)
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let contextString = try? container.decode(String.self) {
            self.context = contextString
            self.dockerfile = nil
            self.args = nil
        } else {
            let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
            self.context = try keyedContainer.decode(String.self, forKey: .context)
            self.dockerfile = try keyedContainer.decodeIfPresent(String.self, forKey: .dockerfile)
            self.args = try keyedContainer.decodeIfPresent([String: String].self, forKey: .args)
        }
    }

    enum CodingKeys: String, CodingKey {
        case context, dockerfile, args
    }
}
