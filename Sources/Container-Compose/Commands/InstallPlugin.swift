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

//
//  InstallPlugin.swift
//  Container-Compose
//

import ArgumentParser
import Foundation
@preconcurrency import Rainbow

/// Where to install the compose plugin.
enum PluginLocation: String, ExpressibleByArgument, CaseIterable {
    /// User-level directory that survives `container` upgrades. Matches the
    /// directory added by apple/container#1618: `$XDG_DATA_HOME/container/plugins`
    /// or, if unset, `~/.local/share/container/plugins`.
    case user

    /// The `container` install root (Homebrew keg). Works on current releases but
    /// is wiped whenever `container` is upgraded.
    case installRoot = "install-root"

    /// Install to both: the user directory (durable, scanned once #1618 lands)
    /// and the install root (so `container compose` works on today's releases).
    case auto
}

/// Installs `container-compose` as a `container` CLI plugin so it can be invoked
/// as `container compose ...`.
///
/// Apple's `container` loads a CLI plugin from `<pluginsDir>/<name>/`, expecting
/// the executable at `bin/<name>` (its name must match the directory) and a
/// `config.toml` that — by omitting `servicesConfig` — marks the plugin as CLI
/// rather than a daemon. The plugin is then run with a plain `execvp`, so a
/// symlink to this binary is all that is required.
public struct InstallPlugin: ParsableCommand {

    /// The plugin name: the directory name, the executable name, and the word
    /// users type after `container` (i.e. `container compose ...`).
    private static let pluginName = "compose"

    public static let configuration: CommandConfiguration = .init(
        commandName: "install-plugin",
        abstract: "Install container-compose as a `container` plugin so you can run `container compose ...`"
    )

    @Option(
        name: .long,
        help: "Where to install: 'user' ($XDG_DATA_HOME; requires apple/container#1618), 'install-root' (libexec/container-plugins, the documented third-party location — survives upgrades unless the package recipe misbehaves, see apple/container#1617), or 'auto' (both)."
    )
    var location: PluginLocation = .auto

    @Option(
        name: .long,
        help: "Explicit plugins directory to install into (e.g. a custom container-plugins dir). Overrides --location."
    )
    var pluginDir: String?

    @Option(
        name: .long,
        help: "The container install root. Auto-detected from the `container` executable on your PATH if omitted."
    )
    var installRoot: String?

    @Option(
        name: .long,
        help: "Path to the container-compose executable to link. Defaults to the copy on your PATH, then this binary."
    )
    var binary: String?

    @Flag(name: .long, help: "Remove the installed compose plugin instead of installing it.")
    var uninstall: Bool = false

    public init() {}

    public func run() throws {
        let bases = try targetBaseDirectories()

        if uninstall {
            try runUninstall(bases: bases)
            return
        }

        let binaryURL = try resolveBinary()
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            throw PluginInstallError.binaryNotExecutable(binaryURL.path)
        }

        for base in bases {
            let pluginPath = try install(into: base, linking: binaryURL)
            print("Installed the compose plugin into \(pluginPath.path)".green)
        }

        if usesUserDir {
            print("Note: the user directory is scanned by `container` once apple/container#1618 lands.".yellow)
        }
        print("You can now run \("container compose".bold) (e.g. \("container compose up".cyan)).")
        print("Re-run \("container-compose install-plugin".bold) after upgrading `container`.")
    }

    // MARK: - Install / uninstall

    /// Builds the `<base>/compose/{bin/compose, config.toml}` layout, rebuilding
    /// from scratch so re-running (e.g. after a `container` upgrade) always
    /// produces a clean, correct result. Returns the plugin directory.
    private func install(into base: URL, linking binaryURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let pluginPath = base.appendingPathComponent(Self.pluginName)
        do {
            if fileManager.fileExists(atPath: pluginPath.path) {
                try fileManager.removeItem(at: pluginPath)
            }
            let binDir = pluginPath.appendingPathComponent("bin")
            // Creates the plugins base too (e.g. ~/.local/share/container/plugins),
            // which #1618 requires to exist before it will be scanned.
            try fileManager.createDirectory(at: binDir, withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(
                at: binDir.appendingPathComponent(Self.pluginName),
                withDestinationURL: binaryURL
            )
            try Self.pluginConfig.write(
                to: pluginPath.appendingPathComponent("config.toml"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            throw PluginInstallError.installFailed(pluginPath.path, error.localizedDescription)
        }
        return pluginPath
    }

    private func runUninstall(bases: [URL]) throws {
        let fileManager = FileManager.default
        var removedAny = false
        for base in bases {
            let pluginPath = base.appendingPathComponent(Self.pluginName)
            if fileManager.fileExists(atPath: pluginPath.path) {
                try fileManager.removeItem(at: pluginPath)
                print("Removed the compose plugin from \(pluginPath.path)".green)
                removedAny = true
            }
        }
        if !removedAny {
            print("No compose plugin found in any target directory; nothing to remove.")
        }
    }

    // MARK: - Target resolution

    private var usesUserDir: Bool {
        pluginDir == nil && (location == .user || location == .auto)
    }

    /// The plugins base directories to operate on, honoring --plugin-dir and
    /// --location. In `auto`, a missing install root is skipped (with a warning)
    /// rather than failing, since the user directory alone is still useful.
    private func targetBaseDirectories() throws -> [URL] {
        if let pluginDir {
            return [URL(fileURLWithPath: (pluginDir as NSString).expandingTildeInPath)]
        }
        switch location {
        case .user:
            return [Self.userPluginsBase()]
        case .installRoot:
            return [try installRootPluginsBase()]
        case .auto:
            var bases = [Self.userPluginsBase()]
            do {
                bases.append(try installRootPluginsBase())
            } catch {
                FileHandle.standardError.write(Data(
                    "warning: skipping install-root (\(error.localizedDescription))\n".utf8
                ))
            }
            return bases
        }
    }

    /// `<base>/container/plugins`, mirroring apple/container#1618's
    /// `userHomePluginsDir()`: `$XDG_DATA_HOME/container/plugins` when set and
    /// non-empty, otherwise `~/.local/share/container/plugins`.
    ///
    /// Kept pure (environment and home injected) so it can be tested against the
    /// upstream contract without touching the real process environment.
    static func userPluginsBase(environment: [String: String], home: URL) -> URL {
        if let xdg = environment["XDG_DATA_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("container/plugins")
        }
        return home.appendingPathComponent(".local/share/container/plugins")
    }

    private static func userPluginsBase() -> URL {
        userPluginsBase(
            environment: ProcessInfo.processInfo.environment,
            home: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    /// `<installRoot>/libexec/container-plugins` — the third-party plugin
    /// location `container` scans, distinct from the distribution's own
    /// `libexec/container/plugins`, per the maintainer guidance in
    /// apple/container#1617. Third-party plugins installed here are meant to
    /// survive `container` upgrades (upgrade loss is a package-recipe bug,
    /// not a `container` behavior).
    private func installRootPluginsBase() throws -> URL {
        try resolveInstallRoot()
            .appendingPathComponent("libexec")
            .appendingPathComponent("container-plugins")
    }

    /// Resolves the `container` install root, either from `--install-root` or by
    /// locating the `container` executable (which lives at `<installRoot>/bin/container`).
    private func resolveInstallRoot() throws -> URL {
        if let installRoot {
            return URL(fileURLWithPath: (installRoot as NSString).expandingTildeInPath)
        }
        guard let containerURL = Self.locateOnPath("container") else {
            throw PluginInstallError.containerNotFound
        }
        // Resolve symlinks (e.g. /opt/homebrew/bin/container -> ../Cellar/.../bin/container)
        // so we land in the real keg, then strip the trailing `bin/container`.
        return containerURL
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Resolves the container-compose binary to link into the plugin directory.
    private func resolveBinary() throws -> URL {
        if let binary {
            return URL(fileURLWithPath: (binary as NSString).expandingTildeInPath)
        }
        // Prefer the stable PATH entry (e.g. /opt/homebrew/bin/container-compose)
        // so the link survives container-compose upgrades; fall back to the
        // running executable.
        if let onPath = Self.locateOnPath("container-compose") {
            return onPath
        }
        if let executable = Bundle.main.executableURL {
            return executable
        }
        return URL(fileURLWithPath: CommandLine.arguments[0])
    }

    /// Returns the first executable named `name` found on `PATH`.
    private static func locateOnPath(_ name: String) -> URL? {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        let fileManager = FileManager.default
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// The plugin manifest. Omitting `servicesConfig` marks this as a CLI plugin;
    /// `abstract` is shown as its help text under `container --help`.
    private static let pluginConfig = """
        abstract = "Define and run multi-container applications with Docker Compose files"
        author = "container-compose"
        version = 0.1
        """
}

public enum PluginInstallError: Error, LocalizedError {
    case containerNotFound
    case binaryNotExecutable(String)
    case installFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .containerNotFound:
            return "Could not find the `container` executable on your PATH. Pass --install-root to point at where container is installed, or use --location user."
        case .binaryNotExecutable(let path):
            return "container-compose was not found or is not executable at \(path). Pass --binary to specify it explicitly."
        case .installFailed(let path, let reason):
            return "Failed to install the plugin at \(path): \(reason). You may need write access to that directory."
        }
    }
}
