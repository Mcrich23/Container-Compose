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

    @Option(
        name: .long,
        help: "Specify a profile to enable. Can be repeated. Services without a 'profiles' key are always enabled; profiled services are enabled only when one of their profiles is active."
    )
    public var profile: [String] = []

    /// Active profiles from repeated `--profile` flags merged with the
    /// comma-separated `COMPOSE_PROFILES` environment variable (the Compose
    /// spec's documented equivalent, e.g. `COMPOSE_PROFILES=debug,frontend`).
    public var activeProfiles: Set<String> {
        var result = Set(profile)
        if let envProfiles = ProcessInfo.processInfo.environment["COMPOSE_PROFILES"] {
            result.formUnion(
                envProfiles.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            )
        }
        return result
    }
}
