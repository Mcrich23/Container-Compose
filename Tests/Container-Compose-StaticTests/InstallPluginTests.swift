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
@testable import ContainerComposeCore

@Suite("install-plugin parsing")
struct InstallPluginParsingTests {
    @Test("Defaults to the auto location with no overrides")
    func defaults() throws {
        let cmd = try Main.parseAsRoot(["install-plugin"]) as! InstallPlugin
        #expect(cmd.location == .auto)
        #expect(cmd.uninstall == false)
        #expect(cmd.pluginDir == nil)
        #expect(cmd.binary == nil)
        #expect(cmd.installRoot == nil)
    }

    @Test("Parses --location user together with --uninstall")
    func userUninstall() throws {
        let cmd = try Main.parseAsRoot(["install-plugin", "--location", "user", "--uninstall"]) as! InstallPlugin
        #expect(cmd.location == .user)
        #expect(cmd.uninstall == true)
    }

    @Test("Parses --location install-root")
    func installRootLocation() throws {
        let cmd = try Main.parseAsRoot(["install-plugin", "--location", "install-root"]) as! InstallPlugin
        #expect(cmd.location == .installRoot)
    }

    @Test("Parses --plugin-dir, --binary, and --install-root overrides")
    func overrides() throws {
        let cmd = try Main.parseAsRoot([
            "install-plugin",
            "--plugin-dir", "/tmp/plugins",
            "--binary", "/tmp/bin/container-compose",
            "--install-root", "/tmp/root",
        ]) as! InstallPlugin
        #expect(cmd.pluginDir == "/tmp/plugins")
        #expect(cmd.binary == "/tmp/bin/container-compose")
        #expect(cmd.installRoot == "/tmp/root")
    }

    @Test("Rejects an unknown --location value")
    func rejectsUnknownLocation() {
        #expect(throws: (any Error).self) {
            _ = try Main.parseAsRoot(["install-plugin", "--location", "nowhere"])
        }
    }
}

@Suite("User plugin directory resolution")
struct UserPluginsBaseTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    @Test("Falls back to ~/.local/share when XDG_DATA_HOME is unset")
    func fallsBackToLocalShare() {
        let base = InstallPlugin.userPluginsBase(environment: [:], home: home)
        #expect(base.path == "/Users/test/.local/share/container/plugins")
    }

    @Test("Ignores an empty XDG_DATA_HOME, matching the upstream contract")
    func ignoresEmptyXDG() {
        let base = InstallPlugin.userPluginsBase(environment: ["XDG_DATA_HOME": ""], home: home)
        #expect(base.path == "/Users/test/.local/share/container/plugins")
    }

    @Test("Honors a set XDG_DATA_HOME")
    func honorsXDG() {
        let base = InstallPlugin.userPluginsBase(environment: ["XDG_DATA_HOME": "/data"], home: home)
        #expect(base.path == "/data/container/plugins")
    }
}

extension InstallPluginParsingTests {
    @Test("A dangling plugins-base symlink resolves to its target, like Homebrew's keg link")
    func followsDanglingSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let keg = root.appendingPathComponent("Cellar/container/1.0/libexec")
        try FileManager.default.createDirectory(at: keg, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let link = keg.appendingPathComponent("container-plugins")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../../../../libexec/container-plugins")

        let resolved = InstallPlugin.followingSymlink(link)
        #expect(resolved.standardizedFileURL.path == root.appendingPathComponent("libexec/container-plugins").standardizedFileURL.path)
    }

    @Test("A real directory is returned unchanged")
    func leavesDirectoriesAlone() {
        let dir = FileManager.default.temporaryDirectory
        #expect(InstallPlugin.followingSymlink(dir) == dir)
    }
}
