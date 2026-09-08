//===----------------------------------------------------------------------===//
// Copyright © 2025 Morris Richman and the Container-Compose project authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import Testing
import Foundation
@testable import Yams
@testable import ContainerComposeCore

@Suite("Compose Value Interpolation")
struct NetworkNameInterpolationTests {

    /// The fields a compose file is allowed to parameterise are resolved one at a
    /// time in this project rather than in a single pass after parsing, so each
    /// new field is a chance to forget. This list is the record of which ones are
    /// covered; extend it rather than adding a one-off test elsewhere.
    ///
    /// Measured against a real 23-service compose file: `image` appeared with a
    /// variable in 19 services and `labels` in 2, and both reached `container`
    /// verbatim before this was fixed ("invalid format for image reference").
    /// Variable names here are deliberately implausible. `resolveVariable` gives
    /// the process environment precedence over the map it is handed, which is the
    /// Compose rule (a shell value beats a .env value) - so a test that picks a
    /// name a developer might really export becomes environment-dependent and
    /// fails only on some machines. This bit the author: an earlier draft used
    /// LLDAP_VERSION, which was already exported, and the override case failed
    /// while the identical network-name test passed.
    @Test("image references are interpolated")
    func imageInterpolates() throws {
        let svc = try YAMLDecoder().decode(Service.self, from: """
        image: docker.io/lldap/lldap:${CC_TEST_IMAGE_TAG:-2026-05-26-alpine}
        """)
        let image = try #require(svc.image)

        #expect(
            ComposeUp.resolvedImageReference(image, environment: ["CC_TEST_IMAGE_TAG": "2026-06-01"])
                == "docker.io/lldap/lldap:2026-06-01"
        )

        let defaulted = ComposeUp.resolvedImageReference(image, environment: [:])
        #expect(defaulted == "docker.io/lldap/lldap:2026-05-26-alpine")
        #expect(defaulted.contains("${") == false)
    }

    @Test("label values are interpolated")
    func labelsInterpolate() throws {
        let svc = try YAMLDecoder().decode(Service.self, from: """
        image: alpine
        labels:
          traefik.http.routers.app.rule: Host(`${CC_TEST_APP_HOST:-app.local}`)
        """)
        let args = ComposeUp.labelRunArgs(
            for: svc,
            serviceName: "web",
            projectName: "proj",
            environment: ["CC_TEST_APP_HOST": "app.example.com"]
        )
        // labelRunArgs returns a flat argv: ["--label", "key=value", ...]
        #expect(args.contains("traefik.http.routers.app.rule=Host(`app.example.com`)"))
        #expect(args.contains { $0.contains("${") } == false)
    }

    @Test("the compose project and service labels are always emitted")
    func composeLabelsAlwaysPresent() throws {
        let svc = try YAMLDecoder().decode(Service.self, from: "image: alpine")
        let args = ComposeUp.labelRunArgs(
            for: svc,
            serviceName: "web",
            projectName: "proj",
            environment: [:]
        )
        #expect(args.contains("com.docker.compose.project=proj"))
        #expect(args.contains("com.docker.compose.service=web"))
    }

    @Test("the compose labels win over a user label of the same key")
    func composeLabelsTakePrecedence() throws {
        let svc = try YAMLDecoder().decode(Service.self, from: """
        image: alpine
        labels:
          com.docker.compose.project: user-supplied
        """)
        let args = ComposeUp.labelRunArgs(
            for: svc,
            serviceName: "web",
            projectName: "proj",
            environment: [:]
        )
        #expect(args.contains("com.docker.compose.project=proj"))
        #expect(args.contains("com.docker.compose.project=user-supplied") == false)
    }

    @Test("label argv is sorted, so the command line is deterministic")
    func labelArgvIsSorted() throws {
        let svc = try YAMLDecoder().decode(Service.self, from: """
        image: alpine
        labels:
          zzz: last
          aaa: first
        """)
        let args = ComposeUp.labelRunArgs(
            for: svc, serviceName: "web", projectName: "proj", environment: [:]
        )
        let keys = stride(from: 1, to: args.count, by: 2).map { args[$0].split(separator: "=")[0] }
        #expect(keys == keys.sorted())
    }

    @Test("the process environment wins over the supplied map, as Compose specifies")
    func processEnvironmentTakesPrecedence() throws {
        // PATH is always set and never something a compose file would name, so it
        // pins the precedence rule without depending on the developer's shell.
        let fromProcess = ProcessInfo.processInfo.environment["PATH"]
        let resolved = resolveVariable("${PATH}", with: ["PATH": "ignored-by-design"])
        #expect(resolved == fromProcess)
        #expect(resolved != "ignored-by-design")
    }

    private func network(_ yaml: String) throws -> Network {
        try YAMLDecoder().decode(Network.self, from: yaml)
    }

    @Test("an explicit name is interpolated")
    func explicitNameInterpolates() throws {
        let net = try network("name: ${CC_TEST_INGRESS_NET}")
        let resolved = ComposeUp.resolvedNetworkName(
            key: "reverse-proxy",
            config: net,
            environment: ["CC_TEST_INGRESS_NET": "prod-ingress"]
        )
        #expect(resolved == "prod-ingress")
    }

    @Test("a default value is used when the variable is unset")
    func defaultValueIsHonoured() throws {
        let net = try network("name: ${CC_TEST_INGRESS_NET:-local-ingress}")
        let resolved = ComposeUp.resolvedNetworkName(
            key: "reverse-proxy",
            config: net,
            environment: [:]
        )
        #expect(resolved == "local-ingress")
    }

    @Test("the environment wins over the default")
    func environmentBeatsDefault() throws {
        let net = try network("name: ${CC_TEST_INGRESS_NET:-local-ingress}")
        let resolved = ComposeUp.resolvedNetworkName(
            key: "reverse-proxy",
            config: net,
            environment: ["CC_TEST_INGRESS_NET": "dev-cluster-ingress"]
        )
        #expect(resolved == "dev-cluster-ingress")
    }

    @Test("without an explicit name the key is used, and is itself interpolated")
    func keyFallbackAlsoInterpolates() throws {
        #expect(
            ComposeUp.resolvedNetworkName(key: "dcf-db", config: nil, environment: [:])
                == "dcf-db"
        )
        #expect(
            ComposeUp.resolvedNetworkName(
                key: "${CC_TEST_NET_PREFIX}-db",
                config: nil,
                environment: ["CC_TEST_NET_PREFIX": "dcf"]
            ) == "dcf-db"
        )
    }

    @Test("a plain name is passed through unchanged")
    func plainNameUnchanged() throws {
        let net = try network("name: dcf-vpc")
        #expect(
            ComposeUp.resolvedNetworkName(key: "vpc", config: net, environment: ["X": "y"])
                == "dcf-vpc"
        )
    }
}

/// The suite above pins `resolvedNetworkName` itself. These pin its *consumers*.
///
/// Both consumers used to read the declared `name:` raw, so a compose file
/// saying `name: ${VAR:-default}` had its network created under the resolved
/// name and then asked `container run` to join the literal — and the
/// host-gateway lookup to inspect it. Every test above stayed green throughout,
/// because none of them went through the code `configService` actually calls.
@Suite("Network Args Through A Compose Document")
struct NetworkRunArgsTests {

    private static let yaml = """
    services:
      web:
        image: nginx
        networks:
          - ingress
          - plain
      loner:
        image: nginx
    networks:
      ingress:
        name: ${CC_TEST_INGRESS:-fallback-ingress}
      plain: {}
    """

    private func compose() throws -> DockerCompose {
        try YAMLDecoder().decode(DockerCompose.self, from: Self.yaml)
    }

    private func service(_ name: String) throws -> Service {
        try #require(try compose().services[name] ?? nil)
    }

    /// `supportsAliases` is passed explicitly everywhere here: its default is
    /// probed from the installed `container` CLI, which would make these depend
    /// on the host.
    @Test("the --network arg carries the created name, not the declared literal")
    func connectsUnderCreatedName() throws {
        let args = ComposeUp.networkRunArgs(
            for: try service("web"), dockerCompose: try compose(),
            serviceName: "web", environment: [:], supportsAliases: false
        ).args
        #expect(args == ["--network", "fallback-ingress", "--network", "plain"])
    }

    @Test("the environment wins over the declared default")
    func environmentBeatsDefault() throws {
        let args = ComposeUp.networkRunArgs(
            for: try service("web"), dockerCompose: try compose(),
            serviceName: "web", environment: ["CC_TEST_INGRESS": "prod-ingress"],
            supportsAliases: false
        ).args
        #expect(args == ["--network", "prod-ingress", "--network", "plain"])
    }

    @Test("no placeholder ever reaches the command line")
    func noPlaceholderSurvives() throws {
        let args = ComposeUp.networkRunArgs(
            for: try service("web"), dockerCompose: try compose(),
            serviceName: "web", environment: [:], supportsAliases: false
        ).args
        #expect(!args.contains { $0.contains("${") })
    }

    @Test("a service with no networks contributes no args")
    func noNetworksNoArgs() throws {
        let result = ComposeUp.networkRunArgs(
            for: try service("loner"), dockerCompose: try compose(),
            serviceName: "loner", environment: [:], supportsAliases: false)
        #expect(result.args.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test("the host-gateway lookup uses the created name of the first network")
    func gatewayUsesCreatedName() throws {
        #expect(
            ComposeUp.gatewayNetworkName(
                for: try service("web"), dockerCompose: try compose(),
                environment: ["CC_TEST_INGRESS": "prod-ingress"]) == "prod-ingress")
    }

    @Test("a service with no networks falls back to the default network")
    func gatewayFallsBackToDefault() throws {
        #expect(
            ComposeUp.gatewayNetworkName(
                for: try service("loner"), dockerCompose: try compose(), environment: [:])
                == "default")
    }
}
