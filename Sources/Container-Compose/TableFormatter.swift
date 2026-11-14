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
//  TableFormatter.swift
//  Container-Compose
//
//  Shared presentation helper for subcommands that render aligned tables.
//

/// Minimal left-aligned, space-padded table renderer.
enum TableFormatter {
    static func render(header: [String], rows: [[String]]) -> String {
        let allRows = [header] + rows
        let columnCount = header.count
        var widths = [Int](repeating: 0, count: columnCount)
        for row in allRows {
            for (index, cell) in row.enumerated() where index < columnCount {
                widths[index] = max(widths[index], cell.count)
            }
        }

        func format(_ row: [String]) -> String {
            row.enumerated()
                .map { index, cell in
                    // Don't pad the trailing column — avoids dangling whitespace.
                    index == columnCount - 1 ? cell : cell.padding(toLength: widths[index] + 3, withPad: " ", startingAt: 0)
                }
                .joined()
        }

        return allRows.map(format).joined(separator: "\n")
    }
}
