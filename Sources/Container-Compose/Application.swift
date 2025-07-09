//
//  File.swift
//  Container-Compose
//
//  Created by Morris Richman on 6/18/25.
//

import Foundation
import Yams
import ArgumentParser
import ContainerCLI

@main
struct Application: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "container-compose",
        abstract: "A tool to use manage Docker Compose files with Apple Container",
        subcommands: [
            ContainerCLI.Application.ComposeUp.self,
            ContainerCLI.Application.ComposeDown.self
        ])
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
