import Foundation
import Yams

/// Expands Compose variables once, leaving substituted values and escaped dollars literal.
struct ComposeInterpolation {
    let environment: [String: String]
    var warning: (String) -> Void = { print("Warning: \($0)") }

    enum Failure: Error, CustomStringConvertible {
        case invalidExpression(String)
        case required(String, String)
        case nestingLimit

        var description: String {
            switch self {
            case .invalidExpression(let value): return "Invalid Compose variable expression: \(value)"
            case .required(let name, let message): return "Required variable '\(name)': \(message)"
            case .nestingLimit: return "Compose variable expressions are nested too deeply"
            }
        }
    }

    func expand(_ value: String) throws -> String { try expand(value, depth: 0) }

    private func expand(_ value: String, depth: Int) throws -> String {
        guard depth < 64 else { throw Failure.nestingLimit }
        let chars = Array(value)
        var result = ""
        var index = 0
        while index < chars.count {
            guard chars[index] == "$", index + 1 < chars.count else {
                result.append(chars[index]); index += 1; continue
            }
            let next = chars[index + 1]
            if next == "$" { result.append("$"); index += 2; continue }
            if next == "{" {
                let start = index + 2
                var end = start
                var nesting = 1
                while end < chars.count {
                    if chars[end] == "{" { nesting += 1 }
                    if chars[end] == "}" { nesting -= 1 }
                    if nesting == 0 { break }
                    end += 1
                }
                guard end < chars.count else { throw Failure.invalidExpression(String(chars[index...])) }
                result += try expression(String(chars[start..<end]), depth: depth)
                index = end + 1
            } else if Self.isStart(next) {
                var end = index + 2
                while end < chars.count && Self.isName(chars[end]) { end += 1 }
                result += lookup(String(chars[(index + 1)..<end]))
                index = end
            } else {
                result.append("$"); index += 1
            }
        }
        return result
    }

    private func expression(_ expression: String, depth: Int) throws -> String {
        let chars = Array(expression)
        guard let first = chars.first, Self.isStart(first) else { throw Failure.invalidExpression(expression) }
        var end = 1
        while end < chars.count && Self.isName(chars[end]) { end += 1 }
        let name = String(chars[..<end])
        if end == chars.count { return lookup(name) }
        let remainder = String(chars[end...])
        guard let operation = [":-", ":?", ":+", "-", "?", "+"].first(where: { remainder.hasPrefix($0) }) else {
            throw Failure.invalidExpression(expression)
        }
        let value = environment[name]
        let present = value != nil && (!operation.hasPrefix(":") || !value!.isEmpty)
        let word = String(remainder.dropFirst(operation.count))
        switch operation.last {
        case "-": return present ? value! : try expand(word, depth: depth + 1)
        case "+": return present ? try expand(word, depth: depth + 1) : ""
        default:
            guard present else {
                throw Failure.required(name, try expand(word.isEmpty ? "a value is required" : word, depth: depth + 1))
            }
            return value!
        }
    }

    private func lookup(_ name: String) -> String {
        guard let value = environment[name] else {
            warning("Variable '\(name)' is not set; using an empty string.")
            return ""
        }
        return value
    }

    private static func isStart(_ char: Character) -> Bool {
        char == "_" || char.isASCII && char.isLetter
    }
    private static func isName(_ char: Character) -> Bool { isStart(char) || char.isASCII && char.isNumber }

    /// Expands YAML values before typed decoding. Mapping keys are never interpolated.
    func expandValues(in node: Node) throws -> Node {
        switch node {
        case .scalar(let scalar):
            guard node.tag == Tag(.str) else { return node }
            let expanded = try expand(scalar.string)
            // Yams rejects string-tagged booleans even when decoding a Bool.
            // Keep empty strings and literal "null" as strings after substitution.
            let isExpandedBoolean = scalar.string.contains("$") && ["true", "false"].contains(expanded.lowercased())
            return Node(expanded, isExpandedBoolean ? Tag(.bool) : node.tag, scalar.style)
        case .sequence(let sequence):
            return Node(try sequence.map { try expandValues(in: $0) }, node.tag)
        case .mapping(let mapping):
            return Node(try mapping.map { ($0.key, try expandValues(in: $0.value)) }, node.tag)
        case .alias:
            return node
        }
    }
}
