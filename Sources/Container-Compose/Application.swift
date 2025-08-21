//
//  File.swift
//  Container-Compose
//
//  Created by Morris Richman on 6/18/25.
//

import Foundation
import ArgumentParser
import ComposeCLI

@main
struct Application: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "container-compose",
        abstract: "A tool to use manage Docker Compose files with Apple Container",
        subcommands: [
            ComposeCLI.ComposeUp.self,
            ComposeCLI.ComposeDown.self
        ])
}
