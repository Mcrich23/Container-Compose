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
    private static let commandName: String = "container-compose"
    private static let version: String = "v0.5.1"
    public static var versionString: String {
        "\(commandName) version \(version)"
    }
    static let configuration: CommandConfiguration = .init(
        commandName: Self.commandName,
        abstract: "A tool to use manage Docker Compose files with Apple Container",
        version: Self.versionString,
        subcommands: [
            ComposeUp.self,
            ComposeDown.self,
            Version.self
        ])
}
