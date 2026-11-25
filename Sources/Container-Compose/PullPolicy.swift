import ArgumentParser
import ContainerAPIClient
import ContainerizationOCI

/// Controls registry access when preparing a service image.
public enum PullPolicy: String, Codable, Hashable {
    case always, never, missing, ifNotPresent = "if_not_present", build

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let policy = Self(rawValue: value) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unsupported pull_policy '\(value)'. Supported: always, never, missing, if_not_present, build. Time-based policies require pull timestamps and are not supported."))
        }
        self = policy
    }

    func shouldPull(image: String, local: Bool) -> Bool {
        switch self {
        case .always: return true
        case .never, .build: return false
        case .missing, .ifNotPresent:
            return !local || (!image.contains("@") && (image.hasSuffix(":latest") || !(image.split(separator: "/").last?.contains(":") ?? false)))
        }
    }

    static func isLocal(_ reference: String, platform: String?) async throws -> Bool {
        let config = try await ClientHealthCheck.loadContainerSystemConfig()
        let normalized = try ClientImage.normalizeReference(reference, containerSystemConfig: config)
        guard let image = try await ClientImage.list().first(where: { $0.reference == normalized }) else { return false }
        if let platform {
            let requested = try Platform(from: platform)
            // A stored index can exist without the requested platform's content.
            do { _ = try await image.config(for: requested) } catch { return false }
        }
        return true
    }
}
