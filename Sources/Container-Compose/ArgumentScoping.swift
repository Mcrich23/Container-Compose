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
//  swift-argument-parser merges a parent command and its subcommands into a
//  single flag namespace, so a short flag can only mean one thing across the
//  whole tool. The root owns `-f`/`--file`, which means a subcommand cannot
//  independently rebind `-f` (e.g. `docker compose logs -f` for "follow").
//
//  `cobra` (Docker's CLI library) avoids this by scoping flags positionally:
//  the parent's flags are parsed before the subcommand name, the child's after.
//  We reproduce *only that small slice* of behavior here, opt-in per subcommand,
//  by normalizing argv before ArgumentParser ever sees it: a short flag typed in
//  a subcommand's segment is rewritten to the long form that subcommand wants.
//
//  This is deliberately narrow. Add an entry to `scopedShortFlagOverrides` to
//  opt a specific subcommand into rebinding a specific short flag; everything
//  else is passed through untouched.
//

import Foundation

/// Per-subcommand short-flag rebindings, applied only within that subcommand's
/// argument segment. Keyed by subcommand name, then by the short flag the user
/// types, mapping to the long flag ArgumentParser should receive.
///
/// Example: under `logs`, a bare `-f` means `--follow` (like `docker compose
/// logs -f`), even though `-f` is `--file` everywhere else in the tool.
let scopedShortFlagOverrides: [String: [String: String]] = [
    "logs": ["-f": "--follow"]
]

/// Root-level options that consume the *following* token as their value. We skip
/// past that value when scanning for the subcommand boundary, so a value that
/// happens to equal a subcommand name (e.g. `-f up logs`) isn't mistaken for the
/// subcommand itself.
private let rootValueTakingFlags: Set<String> = ["-f", "--file"]

/// Rewrites argv so that subcommands listed in `scopedShortFlagOverrides` can
/// rebind a short flag within their own segment, without disturbing the root's
/// use of that flag.
///
/// Scanning model (mirrors cobra's positional scoping):
///   - Tokens before the first recognized subcommand are the *root* segment.
///     Root value-taking flags consume their following token.
///   - The first token matching a known subcommand name switches us into the
///     *subcommand* segment; from there, that subcommand's overrides apply.
///   - A `--` terminator ends rewriting; everything after it is passed verbatim.
///
/// Only an exact short-flag token (e.g. `-f`) is rewritten. Attached or combined
/// forms (`-ffile`, `--file=x`, `-fd`) are intentionally left untouched — they
/// are unambiguous to ArgumentParser as written, and expanding them would mean
/// reimplementing a full option parser here.
///
/// - Parameters:
///   - argv: The raw arguments (NOT including the executable name).
///   - subcommands: The set of known subcommand names.
/// - Returns: The normalized arguments to hand to ArgumentParser.
public func normalizeScopedFlags(_ argv: [String], subcommands: Set<String>) -> [String] {
    var out: [String] = []
    out.reserveCapacity(argv.count)

    var activeSubcommand: String? = nil
    var index = 0

    while index < argv.count {
        let token = argv[index]

        // `--` ends option processing entirely; copy the remainder verbatim.
        if token == "--" {
            out.append(contentsOf: argv[index...])
            break
        }

        if let activeSubcommand {
            // Inside a subcommand's segment: apply its overrides, if any.
            if let mapped = scopedShortFlagOverrides[activeSubcommand]?[token] {
                out.append(mapped)
            } else {
                out.append(token)
            }
            index += 1
            continue
        }

        // Root segment.
        if rootValueTakingFlags.contains(token) {
            // Emit the flag and its value together so the value can't be
            // misread as the subcommand boundary.
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
    /// Subcommand names recognized at the top level, derived from the command
    /// configuration so this stays in sync as subcommands are added. Includes
    /// the implicit `help` subcommand ArgumentParser provides.
    public static var subcommandNames: Set<String> {
        var names = Set(configuration.subcommands.compactMap { $0.configuration.commandName })
        names.insert("help")
        return names
    }

    /// Convenience entry point that normalizes scoped short flags before parsing.
    public static func main(normalizing argv: [String]) async {
        await main(normalizeScopedFlags(argv, subcommands: subcommandNames))
    }
}
