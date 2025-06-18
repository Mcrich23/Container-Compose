//
//  Errors.swift
//  Container-Compose
//
//  Created by Morris Richman on 6/18/25.
//

import Foundation

enum YamlError: Error, LocalizedError {
    case dockerfileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .dockerfileNotFound(let path):
            return "docker-compose.yml not found at \(path)"
        }
    }
}
