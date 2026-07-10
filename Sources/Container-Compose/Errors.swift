//===----------------------------------------------------------------------===//
// Copyright © 2025 Morris Richman and the Container-Compose project authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

//
//  Errors.swift
//  Container-Compose
//
//  Created by Morris Richman on 6/18/25.
//

import ContainerCommands
import Foundation

//extension Application {
public enum YamlError: Error, LocalizedError {
    case composeFileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .composeFileNotFound(let path):
            return "compose.yml not found at \(path)"
        }
    }
}

public enum ComposeError: Error, LocalizedError {
    case imageNotFound(String)
    case containerRunFailed(String, Int32)
    case dependencyNotStarted(String, String)
    case dependencyNotHealthy(String, String)
    case dependencyNotCompleted(String, String)
    case unsupportedDependencyCondition(String, String, String)
    case healthcheckUnavailable(String)
    case healthcheckFailed(String)

    public var errorDescription: String? {
        switch self {
        case .imageNotFound(let name):
            return "Service \(name) must define either 'image' or 'build'."
        case .containerRunFailed(let service, let exitCode):
            return "Service '\(service)' failed to start (container run exited with status \(exitCode))."
        case .dependencyNotStarted(let service, let dependency):
            return "Service '\(service)' depends on '\(dependency)', but '\(dependency)' has not started."
        case .dependencyNotHealthy(let service, let dependency):
            return "Service '\(service)' depends on '\(dependency)' with condition 'service_healthy', but '\(dependency)' is not healthy."
        case .dependencyNotCompleted(let service, let dependency):
            return "Service '\(service)' depends on '\(dependency)' with condition 'service_completed_successfully', but '\(dependency)' has not completed successfully."
        case .unsupportedDependencyCondition(let service, let dependency, let condition):
            return "Service '\(service)' depends on '\(dependency)' with unsupported condition '\(condition)'."
        case .healthcheckUnavailable(let service):
            return "Service '\(service)' defines a healthcheck but completed before the healthcheck could run."
        case .healthcheckFailed(let service):
            return "Service '\(service)' failed its healthcheck."
        }
    }
}

public enum TerminalError: Error, LocalizedError {
    case commandFailed(String)

    public var errorDescription: String? {
        "Command failed: \(self)"
    }
}

/// An enum representing streaming output from either `stdout` or `stderr`.
public enum CommandOutput {
    case stdout(String)
    case stderr(String)
    case exitCode(Int32)
}
//}
