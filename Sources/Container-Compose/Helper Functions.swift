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
//  Helper Functions.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//

import Foundation
import Yams
import Rainbow
import ContainerCommands

public func resolvedPath(for path: String, relativeTo baseURL: URL) -> String {
    let expandedPath = NSString(string: path).expandingTildeInPath
    return URL(fileURLWithPath: expandedPath, relativeTo: baseURL).standardizedFileURL.path
}


/// Loads environment variables from a .env file.
/// - Parameter path: The full path to the .env file.
/// - Returns: A dictionary of key-value pairs representing environment variables.
public func loadEnvFile(path: String) -> [String: String] {
    var envVars: [String: String] = [:]
    let fileURL = URL(fileURLWithPath: path)
    do {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.split(separator: "\n")
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Ignore empty lines and comments
            if !trimmedLine.isEmpty && !trimmedLine.starts(with: "#") {
                // Parse key=value pairs
                if let eqIndex = trimmedLine.firstIndex(of: "=") {
                    let key = String(trimmedLine[..<eqIndex])
                    let value = String(trimmedLine[trimmedLine.index(after: eqIndex)...])
                    envVars[key] = value
                }
            }
        }
    } catch {
        // print("Warning: Could not read .env file at \(path): \(error.localizedDescription)")
        // Suppress error message if .env file is optional or missing
    }
    return envVars
}

enum ComposeShellSplitError: Error, LocalizedError {
    case trailingEscape
    case unterminatedQuote

    var errorDescription: String? {
        switch self {
        case .trailingEscape:
            return "Command string ends with an unfinished escape."
        case .unterminatedQuote:
            return "Command string contains an unterminated quote."
        }
    }
}

public func composeShellSplit(_ input: String) throws -> [String] {
    enum Quote {
        case single
        case double
    }

    var tokens: [String] = []
    var current = ""
    var quote: Quote?
    var escaping = false
    var tokenStarted = false

    for character in input {
        if escaping {
            current.append(character)
            tokenStarted = true
            escaping = false
            continue
        }

        switch quote {
        case .single:
            if character == "'" {
                quote = nil
            } else {
                current.append(character)
            }
        case .double:
            if character == "\"" {
                quote = nil
            } else if character == "\\" {
                escaping = true
            } else {
                current.append(character)
            }
        case nil:
            if character == "\\" {
                escaping = true
                tokenStarted = true
            } else if character == "'" {
                quote = .single
                tokenStarted = true
            } else if character == "\"" {
                quote = .double
                tokenStarted = true
            } else if character.isWhitespace {
                if tokenStarted {
                    tokens.append(current)
                    current = ""
                    tokenStarted = false
                }
            } else {
                current.append(character)
                tokenStarted = true
            }
        }
    }

    if escaping {
        throw ComposeShellSplitError.trailingEscape
    }
    if quote != nil {
        throw ComposeShellSplitError.unterminatedQuote
    }
    if tokenStarted {
        tokens.append(current)
    }
    return tokens
}

/// Resolves environment variables within a string (e.g., ${VAR:-default}, ${VAR:?error}).
/// This function supports default values and error-on-missing variable syntax.
/// - Parameters:
///   - value: The string possibly containing environment variable references.
///   - envVars: A dictionary of environment variables to use for resolution.
/// - Returns: The string with all recognized environment variables resolved.
public func resolveVariable(_ value: String, with envVars: [String: String]) -> String {
    var resolvedValue = value
    // Regex to find ${VAR}, ${VAR:-default}, ${VAR:?error}
    let regex = try! NSRegularExpression(pattern: #"\$\{([A-Za-z0-9_]+)(:?-(.*?))?(:\?(.*?))?\}"#, options: [])
    
    // Combine process environment with loaded .env file variables, prioritizing process environment
    let combinedEnv = ProcessInfo.processInfo.environment.merging(envVars) { (current, _) in current }
    
    // Loop to resolve all occurrences of variables in the string
    while let match = regex.firstMatch(in: resolvedValue, options: [], range: NSRange(resolvedValue.startIndex..<resolvedValue.endIndex, in: resolvedValue)) {
        guard let varNameRange = Range(match.range(at: 1), in: resolvedValue) else { break }
        let varName = String(resolvedValue[varNameRange])
        
        if let envValue = combinedEnv[varName] {
            // Variable found in environment, replace with its value
            resolvedValue.replaceSubrange(Range(match.range(at: 0), in: resolvedValue)!, with: envValue)
        } else if let defaultValueRange = Range(match.range(at: 3), in: resolvedValue) {
            // Variable not found, but default value is provided, replace with default
            let defaultValue = String(resolvedValue[defaultValueRange])
            resolvedValue.replaceSubrange(Range(match.range(at: 0), in: resolvedValue)!, with: defaultValue)
        } else if match.range(at: 5).location != NSNotFound, let errorMessageRange = Range(match.range(at: 5), in: resolvedValue) {
            // Variable not found, and error-on-missing syntax used, print error and exit
            let errorMessage = String(resolvedValue[errorMessageRange])
            fputs("Error: Missing required environment variable '\(varName)': \(errorMessage)\n", stderr)
            Application.exit(withError: "Error: Missing required environment variable '\(varName)': \(errorMessage)\n")
        } else {
            // Variable not found and no default/error specified, leave as is and break loop to avoid infinite loop
            break
        }
    }
    return resolvedValue
}

/// Derives a project name from the current working directory. It replaces any '.' characters with
/// '_' to ensure compatibility with container naming conventions.
///
/// - Parameter cwd: The current working directory path.
/// - Returns: A sanitized project name suitable for container naming.
public func deriveProjectName(cwd: String) -> String {
    // We need to replace '.' with _ because it is not supported in the container name
    let projectName = URL(fileURLWithPath: cwd).lastPathComponent.replacingOccurrences(of: ".", with: "_")
    return projectName
}

/// Converts Docker Compose port specification into a container run -p format.
/// Handles various formats: "PORT", "HOST:PORT", "IP:HOST:PORT", and optional protocol.
/// - Parameter portSpec: The port specification string from docker-compose.yml.
/// - Returns: A properly formatted port binding for `container run -p`.
public func composePortToRunArg(_ portSpec: String) -> String {
    // Check for protocol suffix (e.g., "/tcp" or "/udp")
    var protocolSuffix = ""
    var portBody = portSpec
    if let slashRange = portSpec.range(of: "/", options: [.backwards]) {
        let afterSlash = portSpec[slashRange.lowerBound...]
        let protocolPart = String(afterSlash)
        if protocolPart == "/tcp" || protocolPart == "/udp" {
            protocolSuffix = protocolPart
            portBody = String(portSpec[..<slashRange.lowerBound])
        }
    }

    let components = portBody.split(separator: ":", maxSplits: 3).map(String.init)
    switch components.count {
    case 1:
        let containerPort = components[0]
        return "0.0.0.0:\(containerPort):\(containerPort)\(protocolSuffix)"
    case 2:
        let hostPart = components[0]
        let containerPart = components[1]
        let hasIPv4 = hostPart.contains(".")
        let hasIPv6 = hostPart.contains(":") && hostPart.hasPrefix("[") && hostPart.hasSuffix("]")
        if hasIPv4 || hasIPv6 {
            return "\(hostPart):\(containerPart)\(protocolSuffix)"
        } else {
            return "0.0.0.0:\(hostPart):\(containerPart)\(protocolSuffix)"
        }
    case 3:
        let ipPart = components[0]
        let hostPart = components[1]
        let containerPart = components[2]
        return "\(ipPart):\(hostPart):\(containerPart)\(protocolSuffix)"
    default:
        return portSpec
    }
}

extension String: @retroactive Error {}

/// A structure representing the result of a command-line process execution.
public struct CommandResult {
    /// The standard output captured from the process.
    public let stdout: String

    /// The standard error output captured from the process.
    public let stderr: String

    /// The exit code returned by the process upon termination.
    public let exitCode: Int32
}

extension NamedColor: @retroactive Codable {

}
