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

/// Splits a Compose `command:`/`entrypoint:` string value into argv-style words.
///
/// Per the Compose spec, the string form of `command`/`entrypoint` is shorthand
/// for the equivalent list form — `command: bundle exec thin -p 3000` means the
/// same thing as `command: ["bundle", "exec", "thin", "-p", "3000"]` — not a
/// `/bin/sh -c "<string>"` wrapper. Decoding a bare string into a single-element
/// array (the previous behavior here) instead passes the whole string as one
/// argv entry to `container run`, so callers relying on the documented
/// string-form shorthand (e.g. `command: sh -c "foo && bar"`, expecting argv
/// `["sh", "-c", "foo && bar"]`) would see it break.
public enum ShellWords {
    /// Tokenizes `input` using POSIX-ish shell word-splitting: unquoted
    /// whitespace separates words, single quotes preserve their contents
    /// literally, double quotes preserve their contents except for `\"`, `\\`,
    /// `\$`, and `` \` `` (which drop the backslash), and a backslash outside
    /// any quotes escapes the following character. This mirrors the tokenizer
    /// Docker Compose itself uses for the string form of `command`/`entrypoint`
    /// (no globbing, variable expansion, or command substitution — those don't
    /// apply here since the result is passed directly as argv, never run
    /// through an actual shell).
    public static func split(_ input: String) -> [String] {
        var words: [String] = []
        var current = ""
        var hasCurrent = false

        enum Quote {
            case none, single, double
        }
        var quote: Quote = .none

        var iterator = input.makeIterator()
        while let char = iterator.next() {
            switch quote {
            case .none:
                switch char {
                case " ", "\t", "\n", "\r":
                    if hasCurrent {
                        words.append(current)
                        current = ""
                        hasCurrent = false
                    }
                case "'":
                    quote = .single
                    hasCurrent = true
                case "\"":
                    quote = .double
                    hasCurrent = true
                case "\\":
                    if let escaped = iterator.next() {
                        current.append(escaped)
                        hasCurrent = true
                    }
                default:
                    current.append(char)
                    hasCurrent = true
                }
            case .single:
                if char == "'" {
                    quote = .none
                } else {
                    current.append(char)
                }
            case .double:
                if char == "\"" {
                    quote = .none
                } else if char == "\\" {
                    if let escaped = iterator.next() {
                        if "\"\\$`".contains(escaped) {
                            current.append(escaped)
                        } else {
                            current.append(char)
                            current.append(escaped)
                        }
                    } else {
                        current.append(char)
                    }
                } else {
                    current.append(char)
                }
            }
        }

        if hasCurrent {
            words.append(current)
        }

        return words
    }
}
