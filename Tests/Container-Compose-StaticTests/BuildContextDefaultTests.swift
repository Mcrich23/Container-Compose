import Testing
import Yams
@testable import ContainerComposeCore

@Suite("Build context defaults")
struct BuildContextDefaultTests {
    @Test(arguments: ["{}", "dockerfile: custom.Dockerfile", "context: null"])
    func omittedContext(_ yaml: String) throws {
        let build = try YAMLDecoder().decode(Build.self, from: yaml)
        #expect(build.context == ".")
    }

    @Test
    func preservesDockerfile() throws {
        let build = try YAMLDecoder().decode(Build.self, from: "dockerfile: custom.Dockerfile")
        #expect(build.dockerfile == "custom.Dockerfile")
    }

    @Test(arguments: ["context: []", "context: {}"])
    func rejectsInvalidContext(_ yaml: String) {
        #expect(throws: (any Error).self) {
            try YAMLDecoder().decode(Build.self, from: yaml)
        }
    }
}
