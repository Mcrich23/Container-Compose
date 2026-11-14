import Testing
import Yams
@testable import ContainerComposeCore

@Suite("Runtime field consumers")
struct RuntimeFieldTests {
    let environment = ["RUNTIME_TEST_IMAGE": "alpine:3", "RUNTIME_TEST_CONTEXT": "src", "RUNTIME_TEST_FILE": "Devfile"]

    @Test func image() throws {
        let service = try YAMLDecoder().decode(Service.self, from: "image: ${RUNTIME_TEST_IMAGE}")
        #expect(runtimeImage(service, serviceName: "web", environment: environment) == "alpine:3")
    }

    @Test func pullPreservesEscapedImage() {
        #expect(ComposePull.resolvedImage(for: Service(image: "$${RUNTIME_TEST_IMAGE}"), environment: environment) == "${RUNTIME_TEST_IMAGE}")
    }

    @Test func buildPaths() throws {
        let build = try YAMLDecoder().decode(Build.self, from: "context: ${RUNTIME_TEST_CONTEXT}\ndockerfile: ${RUNTIME_TEST_FILE}\ntarget: ${RUNTIME_TEST_IMAGE}")
        #expect(runtimeBuildPaths(build, directory: "/project", environment: environment) == ["/project/src", "--file", "/project/src/Devfile", "--target", "alpine:3"])
    }

    @Test func labelsPreserveKeysAndEscapes() {
        #expect(runtimeLabels(["${KEY}": "${RUNTIME_TEST_IMAGE}", "literal": "$${RUNTIME_TEST_IMAGE}"], environment: environment) == ["--label", "${KEY}=alpine:3", "--label", "literal=${RUNTIME_TEST_IMAGE}"])
    }

    @Test func userArguments() {
        #expect(runtimeUserArguments("${RUNTIME_TEST_IMAGE}", environment: environment) == ["--user", "alpine:3"])
        #expect(runtimeUserArguments(nil, environment: environment).isEmpty)
    }

    @Test func escapedAndOrdinaryReferences() {
        #expect(resolveRuntimeField("$${RUNTIME_TEST_IMAGE}/${RUNTIME_TEST_IMAGE}", environment: environment) == "${RUNTIME_TEST_IMAGE}/alpine:3")
    }
}
