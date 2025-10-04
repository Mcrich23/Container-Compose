//
//  File.swift
//  Container-Compose
//
//  Created by Morris Richman on 6/18/25.
//

import Foundation
import ArgumentParser

@main
struct Main: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "container-compose",
        abstract: "A tool to use manage Docker Compose files with Apple Container",
        subcommands: [
            ComposeUp.self,
            ComposeDown.self
        ])
}
