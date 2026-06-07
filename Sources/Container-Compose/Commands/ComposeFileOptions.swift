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

import ArgumentParser
import Foundation

public struct ComposeFileOptions: ParsableArguments, Sendable {
    public init() {}

    @Option(name: [.customShort("f"), .customLong("file")], help: "The path to your Docker Compose file")
    public var composeFilename: String?

    @Option(name: .customLong("project-directory"), help: "Specify an alternate working directory")
    public var projectDirectory: String?

    /// Resolves the effective working directory with priority:
    ///   1. `projectDirectory` (--project-directory flag)
    ///   2. `processCwd` (from Flags.Process)
    ///   3. `FileManager.default.currentDirectoryPath` (fallback)
    public func effectiveCwd(processCwd: String?) -> String {
        if let dir = projectDirectory {
            return resolvedPath(for: dir, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
        }
        return processCwd ?? FileManager.default.currentDirectoryPath
    }
}
