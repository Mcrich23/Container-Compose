import Foundation
import Testing
import Yams
@testable import ContainerComposeCore

struct ComposeInterpolationTests {
    @Test(arguments: [
        ("$SET/${SET}", "value/value"),
        ("${EMPTY:-fallback}/${EMPTY-fallback}", "fallback/"),
        ("${MISSING:-fallback}/${MISSING-fallback}", "fallback/fallback"),
        ("${SET:+yes}/${SET+yes}", "yes/yes"),
        ("${EMPTY:+yes}/${EMPTY+yes}", "/yes"),
        ("${MISSING:+yes}/${MISSING+yes}", "/"),
        ("${MISSING:-${OTHER:-$SET}}", "value"),
        ("$$SET/$${SET}/$$/$5", "$SET/${SET}/$/$5"),
        ("$OPAQUE", "${SET}"),
        ("${EMPTY?required}", ""),
        ("${SET:?required}", "value"),
        ("${SET:-${MISSING:?unused}}", "value")
    ])
    func operators(input: String, expected: String) throws {
        let resolver = ComposeInterpolation(environment: ["SET": "value", "EMPTY": "", "OPAQUE": "${SET}"])
        #expect(try resolver.expand(input) == expected)
    }

    @Test(arguments: ["${EMPTY:?required}", "${MISSING?required}", "${SET/replacement}", "${SET", "${}"])
    func invalidOrRequired(input: String) {
        #expect(throws: ComposeInterpolation.Failure.self) {
            try ComposeInterpolation(environment: ["EMPTY": ""]).expand(input)
        }
    }

    @Test func missingVariablesWarnAndDoNotStopLaterExpansion() throws {
        var warnings: [String] = []
        let resolver = ComposeInterpolation(environment: ["SET": "value"], warning: { warnings.append($0) })
        #expect(try resolver.expand("$MISSING/$SET") == "/value")
        #expect(warnings.count == 1)
    }

    @Test func yamlValuesPreserveKeysAnchorsAndInsertedText() throws {
        let parsed = try Yams.compose(yaml: """
        x-value: &value "$VALUE"
        services:
          web:
            image: *value
            labels:
              "$KEY": "$VALUE"
        """)
        let node = try #require(parsed)
        let expanded = try ComposeInterpolation(environment: ["KEY": "expanded", "VALUE": "text: ${KEY}\nnew line"]).expandValues(in: node)
        let compose = try YAMLDecoder().decode(DockerCompose.self, from: expanded)
        let service = try #require(compose.services["web"] ?? nil)
        #expect(service.image == "text: ${KEY}\nnew line")
        #expect(service.labels == ["$KEY": "text: ${KEY}\nnew line"])
    }

    @Test func typedValuesDecodeAfterExpansion() throws {
        let parsed = try Yams.compose(yaml: """
        services:
          web:
            image: alpine
            privileged: ${PRIVILEGED:-true}
            healthcheck:
              disable: ${DISABLE:-true}
              retries: ${RETRIES:-3}
        """)
        let node = try #require(parsed)
        let expanded = try ComposeInterpolation(environment: [:]).expandValues(in: node)
        let compose = try YAMLDecoder().decode(DockerCompose.self, from: expanded)
        let service = try #require(compose.services["web"] ?? nil)
        #expect(service.privileged == true)
        #expect(service.healthcheck?.disable == true)
        #expect(service.healthcheck?.retries == 3)
    }

    @Test func projectResolutionExpandsNamesAndRuntimeValuesOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "CC_INTERP_NAME=resolved\nCC_INTERP_IMAGE=alpine\nCC_INTERP_KEY=label\nCC_INTERP_VALUE=from-dotenv\nPATH=from-file\n".write(to: directory.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "ORDER=first\n".write(to: directory.appendingPathComponent("first.env"), atomically: true, encoding: .utf8)
        try "ORDER=last\n".write(to: directory.appendingPathComponent("last.env"), atomically: true, encoding: .utf8)
        try """
        name: $CC_INTERP_NAME
        services:
          web:
            container_name: ${CC_INTERP_NAME}-web
            image: $CC_INTERP_IMAGE
            user: ${CC_INTERP_USER:-1000}
            command: [echo, "$$HOME", "$CC_INTERP_VALUE"]
            entrypoint: ["${CC_INTERP_ENTRY:-/bin/sh}", "-c"]
            labels: ["$CC_INTERP_KEY=$CC_INTERP_VALUE"]
            environment:
              LITERAL: $$HOME
              VALUE: $CC_INTERP_VALUE
              PROCESS_PATH: $PATH
            env_file: [first.env, last.env]
            build:
              context: ${CC_INTERP_CONTEXT:-.}
              dockerfile: ${CC_INTERP_DOCKERFILE:-Dockerfile.dev}
              target: ${CC_INTERP_TARGET:-release}
              args: {LITERAL: "$$HOME"}
            networks:
              default:
                aliases: ["${CC_INTERP_NAME}-alias"]
        networks:
          default:
            name: ${CC_INTERP_NAME}-net
        """.write(to: directory.appendingPathComponent("compose.yaml"), atomically: true, encoding: .utf8)
        let options = try ComposeProjectOptions.parse(["--cwd", directory.path])
        let project = try options.resolve()
        let target = try #require(project.services.first)
        let service = target.service
        #expect(project.projectName == "resolved")
        #expect(target.candidateContainerNames.first == "resolved-web")
        #expect(service.container_name == "resolved-web")
        #expect(service.image == "alpine")
        #expect(service.user == "1000")
        #expect(service.command == ["echo", "$HOME", "from-dotenv"])
        #expect(service.entrypoint == ["/bin/sh", "-c"])
        #expect(service.labels == ["label": "from-dotenv"])
        #expect(service.build?.dockerfile == "Dockerfile.dev")
        #expect(service.build?.target == "release")
        #expect(service.build?.args == ["LITERAL": "$HOME"])
        #expect(project.compose.networks?["default"]??.name == "resolved-net")
        #expect(service.networkConfigurations?["default"]?.aliases == ["resolved-alias"])
        let environment = assembleServiceEnvironment(service: service, composeDirectory: directory.path, interpolationEnvironment: [:], interpolate: false)
        #expect(environment == ["ORDER": "last", "LITERAL": "$HOME", "VALUE": "from-dotenv", "PROCESS_PATH": ProcessInfo.processInfo.environment["PATH"]!])
    }
}
