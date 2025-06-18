//
//  Helper Functions.swift
//  container-compose-app
//
//  Created by Morris Richman on 6/17/25.
//

import Foundation
import Yams

/// Loads environment variables from a .env file.
/// - Parameter path: The full path to the .env file.
/// - Returns: A dictionary of key-value pairs representing environment variables.
func loadEnvFile(path: String) -> [String: String] {
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

/// Resolves environment variables within a string (e.g., ${VAR:-default}, ${VAR:?error}).
/// This function supports default values and error-on-missing variable syntax.
/// - Parameters:
///   - value: The string possibly containing environment variable references.
///   - envVars: A dictionary of environment variables to use for resolution.
/// - Returns: The string with all recognized environment variables resolved.
func resolveVariable(_ value: String, with envVars: [String: String]) -> String {
    var resolvedValue = value
    // Regex to find ${VAR}, ${VAR:-default}, ${VAR:?error}
    let regex = try! NSRegularExpression(pattern: "\\$\\{([A-Z0-9_]+)(:?-(.*?))?(:\\?(.*?))?\\}", options: [])
    
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
            exit(1)
        } else {
            // Variable not found and no default/error specified, leave as is and break loop to avoid infinite loop
            break
        }
    }
    return resolvedValue
}

/// A structure representing the result of a command-line process execution.
struct CommandResult {
    /// The standard output captured from the process.
    let stdout: String

    /// The standard error output captured from the process.
    let stderr: String

    /// The exit code returned by the process upon termination.
    let exitCode: Int32
}

/// Runs a command-line tool asynchronously and captures its output and exit code.
///
/// This function uses async/await and `Process` to launch a command-line tool,
/// returning a `CommandResult` containing the output, error, and exit code upon completion.
///
/// - Parameters:
///   - command: The full path to the executable to run (e.g., `/bin/ls`).
///   - args: An array of arguments to pass to the command. Defaults to an empty array.
/// - Returns: A `CommandResult` containing `stdout`, `stderr`, and `exitCode`.
/// - Throws: An error if the process fails to launch.
/// - Example:
/// ```swift
/// let result = try await runCommand("/bin/echo", args: ["Hello"])
/// print(result.stdout) // "Hello\n"
/// ```
func runCommand(_ command: String, args: [String] = []) async throws -> CommandResult {
    return try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            continuation.resume(throwing: error)
            return
        }

        process.terminationHandler = { proc in
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let result = CommandResult(
                stdout: String(decoding: stdoutData, as: UTF8.self),
                stderr: String(decoding: stderrData, as: UTF8.self),
                exitCode: proc.terminationStatus
            )

            continuation.resume(returning: result)
        }
    }
}

/// Launches a detached command-line process without waiting for its output or termination.
///
/// This function is useful when you want to spawn a process that runs in the background
/// independently of the current application. Output streams are redirected to null devices.
///
/// - Parameters:
///   - command: The full path to the executable to launch (e.g., `/usr/bin/open`).
///   - args: An array of arguments to pass to the command. Defaults to an empty array.
/// - Returns: The `Process` instance that was launched, in case you want to retain or manage it.
/// - Throws: An error if the process fails to launch.
/// - Example:
/// ```swift
/// try launchDetachedCommand("/usr/bin/open", args: ["/Applications/Calculator.app"])
/// ```
@discardableResult
func launchDetachedCommand(_ command: String, args: [String] = []) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command)
    process.arguments = args
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice

    // Set this to true to run independently of the launching app
    process.qualityOfService = .background

    try process.run()
    return process
}
