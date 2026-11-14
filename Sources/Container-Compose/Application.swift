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
import ArgumentParser

public struct Main: AsyncParsableCommand {
    /// The standalone executable name.
    static let executableName: String = "container-compose"

    /// The plugin subcommand name. When installed as a `container` CLI plugin the
    /// binary lives at `.../container-plugins/compose/bin/compose`, so `container`
    /// launches it with `argv[0]` basename `compose`.
    static let pluginName: String = "compose"

    private static let version: String = "1.2.0"

    /// The command name shown in help, usage, and error text.
    ///
    /// `container` runs a CLI plugin via `execvp`, passing only the real
    /// subcommand args (it does *not* re-pass the word `compose`). The single
    /// signal that we were invoked as a plugin is `argv[0]`'s basename, which is
    /// `compose` rather than `container-compose`. In that case we render the true
    /// invocation, `container compose`, so help/usage/errors read correctly;
    /// otherwise we keep the standalone name.
    static func displayCommandName(forInvocation invocation: String?) -> String {
        let invokedName = invocation.map { ($0 as NSString).lastPathComponent }
        return invokedName == pluginName ? "container \(pluginName)" : executableName
    }

    private static let commandName: String = displayCommandName(forInvocation: CommandLine.arguments.first)

    public static var versionString: String {
        "\(commandName) version \(version)"
    }
    public static let configuration: CommandConfiguration = .init(
        commandName: Self.commandName,
        abstract: "A tool to use and manage Docker Compose files with Apple Container",
        version: Self.versionString,
        subcommands: [
            ComposeUp.self,
            ComposeDown.self,
            ComposeBuild.self,
            ComposePull.self,
            ComposePs.self,
            ComposeImages.self,
            InstallPlugin.self,
            Version.self
        ])
    
    @OptionGroup
    var composeFileOptions: ComposeFileOptions

    public init() {}
}
