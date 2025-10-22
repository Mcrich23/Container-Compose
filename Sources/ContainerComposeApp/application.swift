//
//  main.swift
//  Container-Compose
//
//  Created by Morris Richman on 6/18/25.
//

import ContainerComposeCore
import ArgumentParser

@main
struct Application: AsyncParsableCommand {
    @Argument(parsing: .captureForPassthrough) var args: [String]
    
    func run() async throws {
        await Main.main(args)
    }
}
