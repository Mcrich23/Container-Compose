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
@testable import ContainerComposeCore

@Suite("Helper Functions Tests")
struct HelperFunctionsTests {
    
    @Test("Derive project name from current working directory - contains dot")
    func testDeriveProjectName() throws {
        var cwd = "/Users/user/Projects/My.Project"
        var projectName = deriveProjectName(cwd: cwd)
        #expect(projectName == "My_Project")

        cwd = ".devcontainers"
        projectName = deriveProjectName(cwd: cwd)
        #expect(projectName == "_devcontainers")
    }

    @Test("Build context with variable default is interpolated and resolved")
    func testBuildContextVariableInterpolated() throws {
        // Regression: `build.context: ${REPOS_PATH:-..}/webapp` was used
        // literally, producing "context dir does not exist .../${REPOS_PATH:-..}/webapp".
        let result = resolveBuildPaths(
            context: "${CC_TEST_REPOS_PATH_UNSET:-..}/webapp",
            dockerfile: nil,
            composeDirectory: "/tmp/project/env"
        )
        #expect(result.contextPath == "/tmp/project/webapp")
        #expect(result.dockerfilePath == "/tmp/project/webapp/Dockerfile")
    }

    @Test("Build context variable resolved from env file")
    func testBuildContextVariableFromEnvFile() throws {
        let result = resolveBuildPaths(
            context: "${CC_TEST_REPOS_PATH_UNSET:-..}/webapp",
            dockerfile: "docker/Dockerfile.dev",
            composeDirectory: "/tmp/project/env",
            environmentVariables: ["CC_TEST_REPOS_PATH_UNSET": "/srv/repos"]
        )
        #expect(result.contextPath == "/srv/repos/webapp")
        #expect(result.dockerfilePath == "/srv/repos/webapp/docker/Dockerfile.dev")
    }

    @Test("Literal build context stays relative to compose directory")
    func testLiteralBuildContext() throws {
        let result = resolveBuildPaths(
            context: ".",
            dockerfile: nil,
            composeDirectory: "/tmp/project/env"
        )
        #expect(result.contextPath == "/tmp/project/env")
        #expect(result.dockerfilePath == "/tmp/project/env/Dockerfile")
    }

    @Test("Container name with variable default is interpolated")
    func testContainerNameVariableInterpolated() throws {
        // Regression: `container_name: ${WEB_CONTAINER:-web-dev}` was
        // used literally, producing an invalid container name.
        let result = resolveContainerName(
            explicit: "${CC_TEST_CONTAINER_UNSET:-web-dev}", projectName: "myproj", serviceName: "web")
        #expect(result == "web-dev")
    }

    @Test("Container name variable resolved from env file")
    func testContainerNameVariableFromEnvFile() throws {
        let result = resolveContainerName(
            explicit: "${CC_TEST_CONTAINER_UNSET:-web-dev}", projectName: "myproj", serviceName: "web",
            envVars: ["CC_TEST_CONTAINER_UNSET": "web-worktree"])
        #expect(result == "web-worktree")
    }

    @Test("Literal explicit container name is used verbatim")
    func testLiteralExplicitContainerName() throws {
        let result = resolveContainerName(explicit: "my-container", projectName: "myproj", serviceName: "web")
        #expect(result == "my-container")
    }

    @Test("Default container name is project-service")
    func testDefaultContainerName() throws {
        let result = resolveContainerName(explicit: nil, projectName: "myproj", serviceName: "web")
        #expect(result == "myproj-web")
    }

    @Test("Service environment value with variable default is interpolated")
    func testServiceEnvDefaultInterpolated() throws {
        // Regression: SERVICE_ID=${SERVICE_ID:-12345} reached
        // the container as a literal string.
        let result = mergeServiceEnvironment(
            base: [:],
            serviceEnvironment: ["SERVICE_ID": "${CC_TEST_SERVICE_ID_UNSET:-12345}"],
            envVars: [:]
        )
        #expect(result["SERVICE_ID"] == "12345")
    }

    @Test("Service environment value resolved from env file")
    func testServiceEnvFromEnvFile() throws {
        let result = mergeServiceEnvironment(
            base: ["DATABASE_HOST": "db"],
            serviceEnvironment: ["DATABASE_HOST": "${DATABASE_HOST_X}", "EXTRA": "literal"],
            envVars: ["DATABASE_HOST_X": "db-resolved"]
        )
        #expect(result["DATABASE_HOST"] == "db-resolved")
        #expect(result["EXTRA"] == "literal")
    }

    @Test("Service environment overrides base env-file values")
    func testServiceEnvOverridesBase() throws {
        let result = mergeServiceEnvironment(
            base: ["MODE": "from-file", "KEEP": "kept"],
            serviceEnvironment: ["MODE": "from-service"],
            envVars: [:]
        )
        #expect(result["MODE"] == "from-service")
        #expect(result["KEEP"] == "kept")
    }

    @Test("Resolve explicit relative paths against base URL")
    func testResolvedPathRelativeSegments() throws {
        let baseURL = URL(fileURLWithPath: "/tmp/project/compose/compose.yml").deletingLastPathComponent()

        #expect(resolvedPath(for: "./file.yaml", relativeTo: baseURL) == "/tmp/project/compose/file.yaml")
        #expect(resolvedPath(for: "../shared/file.yaml", relativeTo: baseURL) == "/tmp/project/shared/file.yaml")
        #expect(resolvedPath(for: "configs/dev/compose.yaml", relativeTo: baseURL) == "/tmp/project/compose/configs/dev/compose.yaml")
    }

    @Test("Resolve absolute and tilde paths without rebasing")
    func testResolvedPathAbsoluteAndTilde() throws {
        let baseURL = URL(fileURLWithPath: "/tmp/project/compose")
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        #expect(resolvedPath(for: "/var/tmp/compose.yaml", relativeTo: baseURL) == "/var/tmp/compose.yaml")
        #expect(resolvedPath(for: "~/compose.yaml", relativeTo: baseURL) == "\(homePath)/compose.yaml")
    }

    @Test("Compose port - simple container port")
    func testPortSimple() throws {
        let result = composePortToRunArg("3000")
        #expect(result == "0.0.0.0:3000:3000")
    }

    @Test("Compose port - host:container same port")
    func testPortHostContainerSame() throws {
        let result = composePortToRunArg("3000:3000")
        #expect(result == "0.0.0.0:3000:3000")
    }

    @Test("Compose port - host:container different ports")
    func testPortHostContainerDifferent() throws {
        let result = composePortToRunArg("8080:3000")
        #expect(result == "0.0.0.0:8080:3000")
    }

    @Test("Compose port - explicit IP binding IPv4")
    func testPortIPv4Binding() throws {
        let result = composePortToRunArg("127.0.0.1:5432:5432")
        #expect(result == "127.0.0.1:5432:5432")
    }

    @Test("Compose port - explicit IP binding IPv6")
    func testPortIPv6Binding() throws {
        let result = composePortToRunArg("[::1]:3000:3000")
        #expect(result == "[::1]:3000:3000")
    }

    @Test("Compose port - with protocol tcp")
    func testPortWithProtocolTCP() throws {
        let result = composePortToRunArg("3000:3000/tcp")
        #expect(result == "0.0.0.0:3000:3000/tcp")
    }

    @Test("Compose port - explicit IP with protocol")
    func testPortIPv4WithProtocol() throws {
        let result = composePortToRunArg("127.0.0.1:5432:5432/tcp")
        #expect(result == "127.0.0.1:5432:5432/tcp")
    }

    @Test("Compose port - explicit IP already with 0.0.0.0")
    func testPortZeroZeroZeroZero() throws {
        let result = composePortToRunArg("0.0.0.0:3000:3000")
        #expect(result == "0.0.0.0:3000:3000")
    }

    @Test("Merged PATH keeps user order and contains all fallback dirs without duplicates")
    func testMergedPathKeepsOrderNoDuplicates() throws {
        let existing = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let result = mergedExecutablePath(existing: existing)
        #expect(result == existing)
        for dir in standardExecutablePathFallback {
            #expect(result.split(separator: ":").filter { $0 == dir }.count == 1)
        }
    }

    @Test("Merged PATH preserves a custom user directory")
    func testMergedPathPreservesCustomDir() throws {
        let result = mergedExecutablePath(existing: "/run/current-system/sw/bin:/usr/bin")
        let entries = result.split(separator: ":").map(String.init)
        #expect(entries.first == "/run/current-system/sw/bin")
        #expect(entries.contains("/run/current-system/sw/bin"))
        for dir in standardExecutablePathFallback {
            #expect(entries.contains(dir))
        }
    }

    @Test("Merged PATH falls back to the standard dirs when PATH is empty or unset")
    func testMergedPathEmptyFallsBack() throws {
        let expected = standardExecutablePathFallback.joined(separator: ":")
        #expect(mergedExecutablePath(existing: nil) == expected)
        #expect(mergedExecutablePath(existing: "") == expected)
    }

}

/// Trait that creates a unique temporary directory before a test runs and removes it after.
/// The directory URL is available inside the test body via `TempDirTrait.current`.
struct TempDirTrait: TestTrait, TestScoping {
    @TaskLocal static var current: URL = FileManager.default.temporaryDirectory

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await TempDirTrait.$current.withValue(tmp) {
            try await function()
        }
    }
}

extension Trait where Self == TempDirTrait {
    /// Provides each test with a fresh temp directory that is removed when the test finishes.
    static var tempDir: TempDirTrait { TempDirTrait() }
}

@Suite("Compose Volume Tests")
struct ComposeVolumeTests {

    @Test("Single-file bind mount with :ro mode is forwarded", .tempDir)
    func testFileMountWithMode() throws {
        let tmp = TempDirTrait.current
        let hostFile = tmp.appending(path: "config.yaml")
        FileManager.default.createFile(atPath: hostFile.path, contents: nil)

        let result = try composeVolumeToRunArgs(
            "\(hostFile.path):/app/config.yaml:ro",
            cwd: tmp.path,
            projectName: "test"
        )
        #expect(result == ["-v", "\(hostFile.path):/app/config.yaml:ro"])
    }

    @Test("Single-file bind mount without mode is forwarded", .tempDir)
    func testFileMountNoMode() throws {
        let tmp = TempDirTrait.current
        let hostFile = tmp.appending(path: "init.sh")
        FileManager.default.createFile(atPath: hostFile.path, contents: nil)

        let result = try composeVolumeToRunArgs(
            "\(hostFile.path):/docker-entrypoint-initdb.d/init.sh",
            cwd: tmp.path,
            projectName: "test"
        )
        #expect(result == ["-v", "\(hostFile.path):/docker-entrypoint-initdb.d/init.sh"])
    }

    @Test("Directory bind mount is forwarded", .tempDir)
    func testDirectoryMount() throws {
        let tmp = TempDirTrait.current
        let dataDir = tmp.appending(path: "data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let result = try composeVolumeToRunArgs(
            "\(dataDir.path):/app/data",
            cwd: tmp.path,
            projectName: "test"
        )
        #expect(result == ["-v", "\(dataDir.path):/app/data"])
    }

    @Test("Directory bind mount with :ro mode preserves mode", .tempDir)
    func testDirectoryMountWithMode() throws {
        let tmp = TempDirTrait.current
        let dataDir = tmp.appending(path: "data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let result = try composeVolumeToRunArgs(
            "\(dataDir.path):/app/data:ro",
            cwd: tmp.path,
            projectName: "test"
        )
        #expect(result == ["-v", "\(dataDir.path):/app/data:ro"])
    }

    @Test("Relative file bind mount resolved to absolute path against cwd", .tempDir)
    func testRelativeFileMountResolvedAgainstCwd() throws {
        let tmp = TempDirTrait.current
        let hostFile = tmp.appending(path: "config.yaml")
        FileManager.default.createFile(atPath: hostFile.path, contents: nil)

        let result = try composeVolumeToRunArgs(
            "./config.yaml:/app/config.yaml:ro",
            cwd: tmp.path,
            projectName: "test"
        )
        #expect(result == ["-v", "\(hostFile.path):/app/config.yaml:ro"])
    }

    @Test("Missing host path is auto-created as a directory", .tempDir)
    func testMissingHostPathAutoCreated() throws {
        let tmp = TempDirTrait.current
        let newDir = tmp.appending(path: "new-volume")
        #expect(!FileManager.default.fileExists(atPath: newDir.path))

        let result = try composeVolumeToRunArgs(
            "\(newDir.path):/app/data",
            cwd: tmp.path,
            projectName: "test"
        )
        #expect(result == ["-v", "\(newDir.path):/app/data"])
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: newDir.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("Invalid volume format returns empty array")
    func testInvalidFormatReturnsEmpty() throws {
        let result = try composeVolumeToRunArgs("nodestination", cwd: "/tmp", projectName: "test")
        #expect(result == [])
    }

}
