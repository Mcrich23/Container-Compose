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
//===----------------------------------------------------------------------===//

// limitations under the License.

import ArgumentParser
import Foundation

struct ComposeDoctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check the installed Apple Container CLI version"
    )

    private static let expectedVersion = "1.7.1"

    func run() throws {
        print(Main.versionString)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["container", "--version"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let response = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw ValidationError("Could not run container --version. \(response)")
        }
        let version = try Self.checkVersion(response)
        print("Apple Container \(version) matches this build.")
    }

    static func checkVersion(_ response: String) throws -> String {
        guard let version = response.wholeMatch(
            of: /container CLI version ([0-9]+\.[0-9]+\.[0-9]+[^\s]*)(?: \([^\r\n]*\))?/
        )?.1 else {
            throw ValidationError("Could not read the Apple Container version from: \(response)")
        }

        guard version == Self.expectedVersion else {
            throw ValidationError(
                "Found Apple Container \(version). This build expects \(Self.expectedVersion). Compatibility with other versions is unverified."
            )
        }

        return String(version)
    }
}
