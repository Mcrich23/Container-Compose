import Testing
import Yams
@testable import ContainerComposeCore

struct ComposeResourceTests {
    @Test func ownershipRequiresBothLabels() {
        #expect(!ComposeResources.owns(["com.docker.compose.project": "app"], project: "app"))
        #expect(ComposeResources.owns(ComposeResources.labels(project: "app"), project: "app"))
        #expect(!ComposeResources.owns(ComposeResources.labels(project: "other"), project: "app"))
    }

    @Test func networkNamesMatchCreationAndAttachment() throws {
        #expect(ComposeResources.networkName("default", config: nil, project: "app") == "app_default")
        let external = try YAMLDecoder().decode(Network.self, from: "external: true")
        #expect(ComposeResources.networkName("shared", config: external, project: "app") == "shared")
        let explicit = try YAMLDecoder().decode(Network.self, from: "name: custom")
        #expect(ComposeResources.networkName("net", config: explicit, project: "app") == "custom")
    }

    @Test func signalsDecodeAndValidate() throws {
        for value in ["SIGUSR1", "USR1", "10"] {
            let service = try YAMLDecoder().decode(Service.self, from: "image: alpine\nstop_signal: '\(value)'")
            #expect(ComposeStopOptions.resolve(for: service).signal == value)
        }
        for value in ["INVALID", "0", "999", ""] {
            #expect(throws: (any Error).self) {
                _ = try YAMLDecoder().decode(Service.self, from: "image: alpine\nstop_signal: '\(value)'")
            }
        }
    }
}
