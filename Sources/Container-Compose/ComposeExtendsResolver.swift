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

import Foundation
import Yams

/// Resolves inheritance using typed, optionally incomplete service fields.
/// YAML nodes are used only at the document boundary; Service validates the result.
struct ComposeExtendsResolver {
    enum ResolutionError: LocalizedError {
        case invalidReference(String)
        case missingFile(String)
        case missingService(String, String)
        case circularReference(String)
        case disabledHealthcheck(String)

        var errorDescription: String? {
            switch self {
            case .invalidReference(let service):
                return "Service '\(service)' has an invalid extends reference (expected a service name or a mapping with service and optional file)."
            case .missingFile(let path):
                return "The extends file '\(path)' could not be found."
            case .missingService(let service, let path):
                return "The extends service '\(service)' was not found in '\(path)'."
            case .circularReference(let chain):
                return "Circular extends reference: \(chain)."
            case .disabledHealthcheck(let service):
                return "Service '\(service)' cannot disable an inherited healthcheck that was not disabled."
            }
        }
    }

    private struct ServiceID: Hashable, CustomStringConvertible {
        let file: URL
        let name: String

        var description: String { "\(file.lastPathComponent):\(name)" }
    }

    private let mainFile: URL
    private let fileManager: FileManager
    private var documents: [URL: Node] = [:]
    private var resolvedServices: [ServiceID: ExtendsService] = [:]

    init(mainFile: URL, yaml: String, fileManager: FileManager = .default) throws {
        self.mainFile = mainFile.standardizedFileURL.resolvingSymlinksInPath()
        self.fileManager = fileManager
        if let document = try Yams.compose(yaml: yaml) {
            documents[self.mainFile] = document
        }
    }

    /// Returns the original YAML unchanged if no service uses `extends`.
    mutating func resolve(_ originalYAML: String) throws -> String {
        guard var document = documents[mainFile],
              case .mapping = document,
              let services = document["services"],
              case .mapping(let serviceMap) = services else {
            return originalYAML
        }

        guard serviceMap.contains(where: { $0.value["extends"] != nil }) else {
            return originalYAML
        }

        var updated = [(Node, Node)]()
        for (key, value) in serviceMap {
            if let name = key.string, value["extends"] != nil {
                let service = try resolveService(ServiceID(file: mainFile, name: name), stack: [])
                let encoded = try YAMLEncoder().encode(service)
                guard let node = try Yams.compose(yaml: encoded) else { throw ResolutionError.invalidReference(name) }
                updated.append((key, node))
            } else {
                updated.append((key, value))
            }
        }
        document["services"] = Node(updated)
        return try Yams.serialize(node: document)
    }

    private mutating func resolveService(_ id: ServiceID, stack: [ServiceID]) throws -> ExtendsService {
        if let first = stack.firstIndex(of: id) {
            throw ResolutionError.circularReference((stack[first...] + [id]).map(\.description).joined(separator: " -> "))
        }
        if let cached = resolvedServices[id] { return cached }
        let document = try loadDocument(id.file)
        guard let node = document["services"]?[id.name] else {
            throw ResolutionError.missingService(id.name, id.file.path)
        }
        guard case .mapping = node else { throw ResolutionError.invalidReference(id.name) }
        var child = try YAMLDecoder().decode(ExtendsService.self, from: Yams.serialize(node: node))
        if id.file != mainFile {
            child = rebasePaths(in: child, from: id.file.deletingLastPathComponent())
        }
        if let reference = child.extends {
            let parentFile = reference.file.map {
                URL(fileURLWithPath: $0, relativeTo: mainFile.deletingLastPathComponent())
                    .standardizedFileURL.resolvingSymlinksInPath()
            } ?? id.file
            let parent = try resolveService(ServiceID(file: parentFile, name: reference.service), stack: stack + [id])
            if child.healthcheck?.disable == true, parent.healthcheck?.disable != true {
                throw ResolutionError.disabledHealthcheck(id.name)
            }
            child = child.inheriting(parent)
        }
        child.extends = nil
        resolvedServices[id] = child
        return child
    }

    private mutating func loadDocument(_ file: URL) throws -> Node {
        if let document = documents[file] { return document }
        guard let data = fileManager.contents(atPath: file.path),
              let yaml = String(data: data, encoding: .utf8) else {
            throw ResolutionError.missingFile(file.path)
        }
        guard let document = try Yams.compose(yaml: yaml) else {
            throw ResolutionError.missingService("services", file.path)
        }
        documents[file] = document
        return document
    }

    /// Anchor inherited paths to the document that declared them.
    private func rebasePaths(in service: ExtendsService, from directory: URL) -> ExtendsService {
        var result = service
        result.env_file = service.env_file?.map { absolutePath($0, from: directory) }
        if let context = service.build?.context {
            result.build?.context = absolutePath(context, from: directory)
        }
        result.volumes = service.volumes?.map { specification in
            let parts = specification.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].hasPrefix(".") else { return specification }
            return absolutePath(String(parts[0]), from: directory) + ":" + parts[1]
        }
        return result
    }

    private func absolutePath(_ path: String, from directory: URL) -> String {
        guard !path.hasPrefix("/"), !path.contains("://") else { return path }
        return URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL.path
    }
}
