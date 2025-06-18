//
//  File.swift
//  Container-Compose
//
//  Created by Morris Richman on 6/18/25.
//

import Foundation
import ArgumentParser

enum Action: String, ExpressibleByArgument, Codable {
    init?(argument: String) {
        self.init(rawValue: argument)
    }
    
    case up
}

@main
struct Application: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "container-compose",
        abstract: "A tool to use manage Docker Compose files with Apple Container"
        )
    
    @Argument(help: "Directs what container-compose should do")
    var action: Action
    
    @Flag(name: [.customShort("d"), .customLong("detach")])
    var detatch: Bool = false
    
    func run() async throws {
        print(action)
    }
}
