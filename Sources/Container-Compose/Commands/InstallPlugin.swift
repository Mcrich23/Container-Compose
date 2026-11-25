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
    /// `$XDG_DATA_HOME/container/plugins` (apple/container#1618).
    case user

    /// `<installRoot>/libexec/container-plugins`, which `container` scans today.
    case installRoot = "install-root"

    /// Both `user` and `installRoot`.
    case auto
}

/// Installs `container-compose` as a `container` CLI plugin, so it runs as
/// `container compose ...`.
///
/// `container` loads `<pluginsDir>/<name>/bin/<name>` and its `config.toml`,
/// then `execvp`s it, so a symlink to this binary suffices.
public struct InstallPlugin: ParsableCommand {

    /// The plugin directory, executable, and subcommand name.
    private static let pluginName = "compose"

    public static let configuration: CommandConfiguration = .init(
        commandName: "install-plugin",
        abstract: "Install container-compose as a `container` plugin so you can run `container compose ...`",
        // Meant for package managers (e.g. a Homebrew post-install), not everyday use.
        shouldDisplay: false
    )

    @Option(
        name: .long,
        help: "Where to install: 'user' ($XDG_DATA_HOME; requires apple/container#1618), 'install-root' (libexec/container-plugins, the documented third-party location), or 'auto' (both)."
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
    }

    // MARK: - Install / uninstall

    /// Builds the `<base>/compose/{bin/compose, config.toml}` layout, rebuilding
    /// from scratch so re-running is idempotent. Returns the plugin directory.
    private func install(into base: URL, linking binaryURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let pluginPath = Self.followingSymlink(base).appendingPathComponent(Self.pluginName)
        do {
            if fileManager.fileExists(atPath: pluginPath.path) {
                try fileManager.removeItem(at: pluginPath)
            }
            let binDir = pluginPath.appendingPathComponent("bin")
            // Also creates the plugins base, which may not exist yet.
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

    /// The plugins directories to act on. In `auto`, a missing install root is
    /// skipped with a warning.
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

    /// `$XDG_DATA_HOME/container/plugins`, or `~/.local/share/container/plugins`
    /// when unset, matching apple/container#1618.
    static func userPluginsBase(environment: [String: String], home: URL) -> URL {
        if let xdg = environment["XDG_DATA_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("container/plugins")
        }
        return home.appendingPathComponent(".local/share/container/plugins")
    }

    /// Resolves `url` if it is a symlink, even a dangling one, so its target can
    /// be created. Homebrew's `container` keg links `libexec/container-plugins`
    /// to `$(brew --prefix)/libexec/container-plugins`, which survives upgrades
    /// but may not exist yet.
    static func followingSymlink(_ url: URL) -> URL {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
            return url
        }
        return URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
    }

    private static func userPluginsBase() -> URL {
        userPluginsBase(
            environment: ProcessInfo.processInfo.environment,
            home: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    /// The third-party plugin directory `container` scans, separate from its
    /// bundled `libexec/container/plugins` (apple/container#1617). Survives
    /// `container` upgrades on both the pkg and Homebrew installs.
    private func installRootPluginsBase() throws -> URL {
        try resolveInstallRoot()
            .appendingPathComponent("libexec")
            .appendingPathComponent("container-plugins")
    }

    /// The `--install-root`, or the directory above `container`'s `bin/`.
    private func resolveInstallRoot() throws -> URL {
        if let installRoot {
            return URL(fileURLWithPath: (installRoot as NSString).expandingTildeInPath)
        }
        guard let containerURL = Self.locateOnPath("container") else {
            throw PluginInstallError.containerNotFound
        }
        // Resolve brew's bin symlink to the keg.
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
        // Prefer the PATH entry: it survives container-compose upgrades.
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
