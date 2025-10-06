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
    static let version: String = "v0.5.1"
    static let configuration: CommandConfiguration = .init(
        commandName: "container-compose",
        abstract: "A tool to use manage Docker Compose files with Apple Container",
        version: Self.version,
        subcommands: [
            ComposeUp.self,
            ComposeDown.self,
            Version.self
        ])
}
