//
//  UIDs.swift
//  Container-Compose
//
//  Created by Morris Richman on 6/11/26.
//

import Foundation

public func makeUID() -> String {
    String(UUID().uuidString.prefix(8))
}

public func makeContainerName() -> String {
    "Container-Compose_Tests_\(makeUID())"
}
