import Testing
import Yams
@testable import ContainerComposeCore

struct BuildArgumentTests {
    @Test func argumentSemantics() throws {
        let build = try YAMLDecoder().decode(Build.self, from: "args: [A=x=y, B, C=, D=$literal]")
        let values = try resolvedBuildArguments(build.args, cli: ["A=cli=$cash", "B"], environment: [:])
        #expect(values == ["A": "cli=$cash", "C": "", "D": "$literal"])
        #expect(try resolvedBuildArguments(["A": nil], environment: ["A": "host"]) == ["A": "host"])
        #expect(throws: (any Error).self) { try parseBuildArgumentEntries(["=bad"]) }
        #expect(throws: (any Error).self) { try YAMLDecoder().decode(Build.self, from: "args: 42") }
        let map = try YAMLDecoder().decode(Build.self, from: "args: {A: null, B: ''}")
        #expect(try resolvedBuildArguments(map.args, environment: [:]) == ["B": ""])
    }
}
