import Testing
import Yams
@testable import ContainerComposeCore

struct ResourceExternalTests {
    private func decodeAll(_ yaml: String) throws {
        _ = try YAMLDecoder().decode(Volume.self, from: yaml)
        _ = try YAMLDecoder().decode(Network.self, from: yaml)
        _ = try YAMLDecoder().decode(Config.self, from: yaml)
        _ = try YAMLDecoder().decode(Secret.self, from: yaml)
    }

    @Test(arguments: ["true", "false", "null", "{name: shared}"])
    func validExternal(_ value: String) throws {
        try decodeAll("external: \(value)")
    }

    @Test(arguments: ["[]", "42", "unexpected", "{}", "{other: shared}", "{name: shared, other: ignored}", "{name: ''}"])
    func malformedExternal(_ value: String) {
        let yaml = "external: \(value)"
        #expect(throws: (any Error).self) { try YAMLDecoder().decode(Volume.self, from: yaml) }
        #expect(throws: (any Error).self) { try YAMLDecoder().decode(Network.self, from: yaml) }
        #expect(throws: (any Error).self) { try YAMLDecoder().decode(Config.self, from: yaml) }
        #expect(throws: (any Error).self) { try YAMLDecoder().decode(Secret.self, from: yaml) }
    }
}
