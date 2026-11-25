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
//  ArgumentScoping.swift
//  Container-Compose
//
//  ArgumentParser gives a command and its subcommands one flag namespace, so
//  `-f` can't mean `--file` at the root and `--follow` under `logs`. This
//  rewrites argv before parsing to scope short flags by position, like cobra.
//

import Foundation

/// Short flags rewritten to a long flag only after the named subcommand.
let scopedShortFlagOverrides: [String: [String: String]] = [
    "logs": ["-f": "--follow"]
]

/// Root options whose value is skipped when finding the subcommand, so
/// `-f up logs` treats `up` as a file name.
private let rootValueTakingFlags: Set<String> = ["-f", "--file"]

/// Applies `scopedShortFlagOverrides` to tokens after the first subcommand.
/// Stops rewriting at `--`.
///
/// - Note: Only exact tokens like `-f` are rewritten; attached or combined
///   forms (`-ffile`, `-fd`) pass through unchanged.
/// - Parameters:
///   - argv: The raw arguments, without the executable name.
///   - subcommands: The set of known subcommand names.
/// - Returns: The normalized arguments to hand to ArgumentParser.
public func normalizeScopedFlags(_ argv: [String], subcommands: Set<String>) -> [String] {
    var out: [String] = []
    out.reserveCapacity(argv.count)

    var activeSubcommand: String? = nil
    var index = 0

    while index < argv.count {
        let token = argv[index]

        if token == "--" {
            out.append(contentsOf: argv[index...])
            break
        }

        if let activeSubcommand {
            if let mapped = scopedShortFlagOverrides[activeSubcommand]?[token] {
                out.append(mapped)
            } else {
                out.append(token)
            }
            index += 1
            continue
        }

        if rootValueTakingFlags.contains(token) {
            out.append(token)
            if index + 1 < argv.count {
                out.append(argv[index + 1])
                index += 2
            } else {
                index += 1
            }
            continue
        }

        if subcommands.contains(token) {
            activeSubcommand = token
        }
        out.append(token)
        index += 1
    }

    return out
}

extension Main {
    /// Top-level subcommand names, including ArgumentParser's implicit `help`.
    public static var subcommandNames: Set<String> {
        var names = Set(configuration.subcommands.compactMap { $0.configuration.commandName })
        names.insert("help")
        return names
    }

    /// Parses `argv` after applying `normalizeScopedFlags`.
    public static func main(normalizing argv: [String]) async {
        await main(normalizeScopedFlags(argv, subcommands: subcommandNames))
    }
}
