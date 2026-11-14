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

import Testing
@testable import ContainerComposeCore

@Suite("ShellWords Tests")
struct ShellWordsTests {

    @Test("Splits plain whitespace-separated words")
    func splitsPlainWords() {
        #expect(ShellWords.split("bundle exec thin -p 3000") == ["bundle", "exec", "thin", "-p", "3000"])
    }

    @Test("Collapses runs of whitespace between words")
    func collapsesRepeatedWhitespace() {
        #expect(ShellWords.split("echo   hello\tworld") == ["echo", "hello", "world"])
    }

    @Test("Empty string produces no words")
    func emptyStringProducesNoWords() {
        #expect(ShellWords.split("") == [])
    }

    @Test("Whitespace-only string produces no words")
    func whitespaceOnlyProducesNoWords() {
        #expect(ShellWords.split("   \t  ") == [])
    }

    @Test("Single word with no whitespace")
    func singleWord() {
        #expect(ShellWords.split("nginx") == ["nginx"])
    }

    @Test("Double-quoted argument preserves internal spaces as one word")
    func doubleQuotedArgumentPreservesSpaces() {
        #expect(ShellWords.split(#"sh -c "echo hello world""#) == ["sh", "-c", "echo hello world"])
    }

    @Test("Single-quoted argument preserves internal spaces as one word")
    func singleQuotedArgumentPreservesSpaces() {
        #expect(ShellWords.split("sh -c 'echo hello world'") == ["sh", "-c", "echo hello world"])
    }

    @Test("Single quotes treat backslashes literally")
    func singleQuotesAreLiteral() {
        #expect(ShellWords.split(#"echo 'a\b'"#) == ["echo", #"a\b"#])
    }

    @Test("Double quotes unescape \\\" and \\\\ but leave other backslashes alone")
    func doubleQuotesUnescapeOnlySpecialChars() {
        #expect(ShellWords.split(#"echo "say \"hi\" \\ done""#) == ["echo", #"say "hi" \ done"#])
        #expect(ShellWords.split(#"echo "C:\path\to\file""#) == ["echo", #"C:\path\to\file"#])
    }

    @Test("Backslash outside quotes escapes the next character, including a space")
    func backslashOutsideQuotesEscapesNextChar() {
        #expect(ShellWords.split(#"echo hello\ world"#) == ["echo", "hello world"])
    }

    @Test("Adjacent quoted and unquoted segments join into a single word")
    func adjacentQuotedAndUnquotedSegmentsJoin() {
        #expect(ShellWords.split(#"echo foo"bar baz"qux"#) == ["echo", "foobar bazqux"])
    }

    @Test("Empty quotes produce an empty-string word")
    func emptyQuotesProduceEmptyWord() {
        #expect(ShellWords.split(#"cmd -e "" next"#) == ["cmd", "-e", "", "next"])
    }

    @Test("Compose spec example: string form matches its documented list-form equivalent")
    func composeSpecStringFormMatchesListForm() {
        // From the Compose spec: `command: bundle exec thin -p 3000` is
        // documented as equivalent to `["bundle", "exec", "thin", "-p", "3000"]`.
        #expect(ShellWords.split("bundle exec thin -p 3000") == ["bundle", "exec", "thin", "-p", "3000"])
    }

    @Test("Realistic multi-flag shell invocation")
    func realisticShellInvocation() {
        #expect(
            ShellWords.split(#"sh -c "sed -i 's/Listen 80/Listen 8080/' /etc/httpd.conf && exec httpd-foreground""#)
                == ["sh", "-c", "sed -i 's/Listen 80/Listen 8080/' /etc/httpd.conf && exec httpd-foreground"]
        )
    }
}
