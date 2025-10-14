//===----------------------------------------------------------------------===//
// Copyright © 2025 Morris Richmna and the Container-Compose project authors. All rights reserved.
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

@main
struct Main: AsyncParsableCommand {
    private static let commandName: String = "container-compose"
    private static let version: String = "v0.5.1"
    static var versionString: String {
        "\(commandName) version \(version)"
    }
    static let configuration: CommandConfiguration = .init(
        commandName: Self.commandName,
        abstract: "A tool to use manage Docker Compose files with Apple Container",
        version: Self.versionString,
        subcommands: [
            ComposeUp.self,
            ComposeDown.self,
            Version.self
        ])
}
