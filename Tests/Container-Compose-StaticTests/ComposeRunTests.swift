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

@Suite("Compose run")
struct ComposeRunTests {
    @Test("Run registered under Main")
    func runRegisteredUnderMain() throws {
        let cmd = try Main.parseAsRoot(["run", "web"]) as! ComposeRun
        #expect(cmd.service == "web")
    }

    @Test("Trailing command overrides service command")
    func trailingCommandOverrides() throws {
        let cmd = try ComposeRun.parse(["web", "python", "app.py"])
        #expect(cmd.service == "web")
        #expect(cmd.command == ["python", "app.py"])
    }

    @Test("Flags parse")
    func flagsParse() throws {
        let cmd = try ComposeRun.parse(["-d", "--rm", "--no-deps", "-P", "--name", "once", "web", "true"])
        #expect(cmd.detach && cmd.rm && cmd.noDeps && cmd.servicePorts)
        #expect(cmd.name == "once")
    }

    @Test("Publish/env/volume/label/entrypoint flags parse")
    func overrideFlagsParse() throws {
        let cmd = try ComposeRun.parse([
            "-p", "8080:80", "-e", "KEY=val", "-v", "data:/data",
            "-l", "a=b", "--entrypoint", "/bin/sh", "web",
        ])
        #expect(cmd.publish == ["8080:80"])
        #expect(cmd.volume == ["data:/data"])
        #expect(cmd.label == ["a=b"])
        #expect(cmd.entrypoint == "/bin/sh")
        #expect(cmd.projectOptions.process.env == ["KEY=val"])
    }

    @Test("One-off name is unique and prefixed")
    func oneOffNameUniquePrefixed() {
        let a = ComposeRun.oneOffContainerName(projectName: "proj", serviceName: "web")
        let b = ComposeRun.oneOffContainerName(projectName: "proj", serviceName: "web")
        #expect(a.hasPrefix("proj-web-run-"))
        #expect(a != b)
    }

    @Test("Label overrides parse")
    func labelOverridesParse() {
        #expect(ComposeRun.parseLabelOverrides(["a=b", "solo"]) == ["a": "b", "solo": ""])
    }

    @Test("Env overrides resolve against base")
    func envOverridesResolve() {
        let out = ComposeRun.parseEnvOverrides(["HOST_PORT=${PORT}"], base: ["PORT": "8080"])
        #expect(out == ["HOST_PORT": "8080"])
    }

    @Test("baseArgs forwards shared options to delegated commands")
    func baseArgsForwardsSharedOptions() throws {
        let cmd = try ComposeRun.parse([
            "-f", "x.yml", "--profile", "dev", "--workdir", "/tmp", "-e", "A=1", "--debug", "web",
        ])
        let args = cmd.baseArgs()
        #expect(args.contains("-f") && args.contains("x.yml"))
        #expect(args.contains("--profile") && args.contains("dev"))
        #expect(args.contains("--workdir") && args.contains("/tmp"))
        #expect(args.contains("-e") && args.contains("A=1"))
        #expect(args.contains("--debug"))
    }

    @Test("One-off hosts path is unique per run and sanitized")
    func oneOffHostsPathUniqueAndSanitized() {
        let first = ComposeUp.runExtraHostsFilePath(projectName: "proj", containerName: "proj-web-run-abc123")
        let second = ComposeUp.runExtraHostsFilePath(projectName: "proj", containerName: "proj-web-run-def456")
        #expect(first != second)
        #expect(first.hasSuffix("proj-web-run-abc123-hosts"))

        let sanitized = ComposeUp.runExtraHostsFilePath(projectName: "proj", containerName: "../evil/name")
        #expect(!sanitized.contains("/evil"))
        #expect(sanitized.hasSuffix(".._evil_name-hosts"))
    }

    @Test("Hosts filename parses back to the container name")
    func hostsFilenameParsesContainerName() {
        let path = ComposeUp.runExtraHostsFilePath(projectName: "proj", containerName: "my-app.web-run-abc")
        let filename = URL(fileURLWithPath: path).lastPathComponent
        #expect(ComposeUp.runContainerName(fromHostsFilename: filename, projectName: "proj") == "my-app.web-run-abc")
    }

    @Test("Hosts filename parsing rejects unrelated and empty names")
    func hostsFilenameParsingRejectsUnrelated() {
        #expect(ComposeUp.runContainerName(fromHostsFilename: "other-file", projectName: "proj") == nil)
        #expect(ComposeUp.runContainerName(fromHostsFilename: "container-compose-other-run-x-hosts", projectName: "proj") == nil)
        #expect(ComposeUp.runContainerName(fromHostsFilename: "container-compose-proj-run--hosts", projectName: "proj") == nil)
    }
}
