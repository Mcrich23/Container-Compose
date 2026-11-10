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

import Foundation
import Testing
import TestHelpers
@testable import ContainerComposeCore

@Suite("Compose extends resolution")
struct ComposeExtendsTests {
    private func write(_ yaml: String, to filename: String, in directory: URL) throws {
        let file = directory.appending(path: filename)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try yaml.write(to: file, atomically: true, encoding: .utf8)
    }

    private func load(in directory: URL) throws -> DockerCompose {
        try ComposeProjectOptions.parse(["--cwd", directory.path]).loadCompose()
    }

    @Test("A same-file child inherits image before service validation", .tempDir)
    func sameFileInheritance() throws {
        let directory = TempDirTrait.current
        try write("""
            services:
              base:
                image: alpine:latest
                environment:
                  BASE: inherited
                  SHARED: parent
              app:
                extends:
                  service: base
                environment:
                  SHARED: child
                command: ["echo", "ready"]
            """, to: "compose.yml", in: directory)

        let compose = try load(in: directory)
        #expect(compose.services["app"]??.image == "alpine:latest")
        #expect(compose.services["app"]??.environment == ["BASE": "inherited", "SHARED": "child"])
        #expect(compose.services["app"]??.command == ["echo", "ready"])
        #expect(compose.services["base"]??.image == "alpine:latest")
    }

    @Test("The same-file shorthand accepted by Docker Compose resolves too", .tempDir)
    func shorthandInheritance() throws {
        let directory = TempDirTrait.current
        try write("""
            services:
              base:
                image: alpine
              app:
                extends: base
                user: guest
            """, to: "compose.yml", in: directory)

        let service = try #require(load(in: directory).services["app"] ?? nil)
        #expect(service.image == "alpine")
        #expect(service.user == "guest")
    }

    @Test("External and chained inheritance do not import unrelated services", .tempDir)
    func externalChain() throws {
        let directory = TempDirTrait.current
        try write("""
            services:
              app:
                extends:
                  file: shared/common.yml
                  service: middle
                environment:
                  APP: yes
            """, to: "compose.yml", in: directory)
        try write("""
            services:
              root:
                image: alpine:latest
                user: root
              middle:
                extends:
                  service: root
                environment:
                  MIDDLE: present
              unrelated:
                image: busybox
            volumes:
              external-data:
            """, to: "shared/common.yml", in: directory)

        let compose = try load(in: directory)
        #expect(compose.services.count == 1)
        #expect(compose.services["app"]??.image == "alpine:latest")
        #expect(compose.services["app"]??.user == "root")
        #expect(compose.services["app"]??.environment == ["APP": "yes", "MIDDLE": "present"])
        #expect(compose.volumes == nil)
    }

    @Test("Field-specific merging replaces commands and volume targets", .tempDir)
    func mergeSemantics() throws {
        let directory = TempDirTrait.current
        try write("""
            services:
              base:
                image: alpine
                environment:
                  - SHARED=base
                  - ONLY_BASE=one
                command: ["sleep", "10"]
                ports: ["80:80", "443:443"]
                volumes:
                  - base:/data:rw
                  - logs:/logs
                env_file: ["base.env"]
              app:
                extends:
                  service: base
                environment:
                  SHARED: child
                  ONLY_CHILD: two
                command: ["echo", "ready"]
                ports: ["80:80", "8080:8080"]
                volumes:
                  - child:/data:ro
                env_file: ["child.env"]
            """, to: "compose.yml", in: directory)

        let service = try #require(load(in: directory).services["app"] ?? nil)
        #expect(service.environment == ["SHARED": "child", "ONLY_BASE": "one", "ONLY_CHILD": "two"])
        #expect(service.command == ["echo", "ready"])
        #expect(service.ports == ["80:80", "443:443", "8080:8080"])
        #expect(service.volumes == ["child:/data:ro", "logs:/logs"])
        #expect(service.env_file == ["base.env", "child.env"])
    }

    @Test("Inherited external paths remain relative to their source file", .tempDir)
    func externalPaths() throws {
        let directory = TempDirTrait.current
        try write("""
            services:
              app:
                extends:
                  file: shared/common.yml
                  service: base
            """, to: "compose.yml", in: directory)
        try write("""
            services:
              base:
                build: ./build-context
                env_file: ./base.env
                volumes:
                  - ./data:/data
                  - named:/named
            """, to: "shared/common.yml", in: directory)

        let service = try #require(load(in: directory).services["app"] ?? nil)
        let shared = directory.appending(path: "shared")
        #expect(service.build?.context == shared.appending(path: "build-context").path)
        #expect(service.env_file == [shared.appending(path: "base.env").path])
        #expect(service.volumes == [shared.appending(path: "data").path + ":/data", "named:/named"])
    }

    @Test("An external service can use YAML anchors without importing its document", .tempDir)
    func externalAnchor() throws {
        let directory = TempDirTrait.current
        try write("""
            services:
              app:
                extends:
                  file: common.yml
                  service: base
            """, to: "compose.yml", in: directory)
        try write("""
            x-common: &common
              image: alpine
              environment:
                SOURCE: external
            services:
              base:
                <<: *common
            """, to: "common.yml", in: directory)

        let service = try #require(load(in: directory).services["app"] ?? nil)
        #expect(service.image == "alpine")
        #expect(service.environment == ["SOURCE": "external"])
    }

    @Test("Nested references resolve file paths from the main Compose file", .tempDir)
    func nestedFileReference() throws {
        let directory = TempDirTrait.current
        try write("""
            services:
              app:
                extends:
                  file: shared/middle.yml
                  service: middle
            """, to: "compose.yml", in: directory)
        try write("""
            services:
              middle:
                extends:
                  file: shared/base.yml
                  service: base
                user: guest
            """, to: "shared/middle.yml", in: directory)
        try write("""
            services:
              base:
                image: alpine
            """, to: "shared/base.yml", in: directory)

        let service = try #require(load(in: directory).services["app"] ?? nil)
        #expect(service.image == "alpine")
        #expect(service.user == "guest")
    }

    @Test("Services without extends keep the existing decoder path", .tempDir)
    func ordinaryService() throws {
        let directory = TempDirTrait.current
        try write("""
            services:
              app:
                image: alpine
                environment:
                  - VALUE=untouched
            """, to: "compose.yml", in: directory)

        let service = try #require(load(in: directory).services["app"] ?? nil)
        #expect(service.image == "alpine")
        #expect(service.environment == ["VALUE": "untouched"])
    }

    @Test("Missing external file and service give explicit errors", .tempDir)
    func missingReferences() throws {
        let directory = TempDirTrait.current
        try write("""
            services:
              app:
                extends:
                  file: missing.yml
                  service: base
            """, to: "compose.yml", in: directory)
        #expect(throws: ComposeExtendsResolver.ResolutionError.self) { try load(in: directory) }

        try write("""
            services:
              base:
                image: alpine
            """, to: "missing.yml", in: directory)
        try write("""
            services:
              app:
                extends:
                  file: missing.yml
                  service: absent
            """, to: "compose.yml", in: directory)
        #expect(throws: ComposeExtendsResolver.ResolutionError.self) { try load(in: directory) }
    }

    @Test("Same-file and cross-file cycles are rejected", .tempDir)
    func cycles() throws {
        let directory = TempDirTrait.current
        try write("""
            services:
              first:
                extends:
                  service: second
              second:
                extends:
                  service: first
            """, to: "compose.yml", in: directory)
        #expect(throws: ComposeExtendsResolver.ResolutionError.self) { try load(in: directory) }

        try write("""
            services:
              first:
                extends:
                  file: other.yml
                  service: second
            """, to: "compose.yml", in: directory)
        try write("""
            services:
              second:
                extends:
                  file: compose.yml
                  service: first
            """, to: "other.yml", in: directory)
        #expect(throws: ComposeExtendsResolver.ResolutionError.self) { try load(in: directory) }
    }

    @Test("A child cannot newly disable an inherited healthcheck", .tempDir)
    func healthcheckRestriction() throws {
        let directory = TempDirTrait.current
        try write("""
            services:
              base:
                image: alpine
                healthcheck:
                  test: ["CMD", "true"]
              child:
                extends:
                  service: base
                healthcheck:
                  disable: true
            """, to: "compose.yml", in: directory)
        #expect(throws: ComposeExtendsResolver.ResolutionError.self) { try load(in: directory) }
    }
}
