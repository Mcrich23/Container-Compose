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

/// Resolves `extends` while service definitions are still YAML. A derived service
/// need not have its own image or build context, so typed decoding must come last.
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
    private var resolvedServices: [ServiceID: Node] = [:]

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
                updated.append((key, try resolveService(ServiceID(file: mainFile, name: name), stack: [])))
            } else {
                updated.append((key, value))
            }
        }
        document["services"] = Node(updated)
        return try Yams.serialize(node: document)
    }

    private mutating func resolveService(_ id: ServiceID, stack: [ServiceID]) throws -> Node {
        if let first = stack.firstIndex(of: id) {
            throw ResolutionError.circularReference((stack[first...] + [id]).map(\.description).joined(separator: " -> "))
        }
        if let cached = resolvedServices[id] { return cached }

        let document = try loadDocument(id.file)
        guard let service = document["services"]?[id.name] else {
            throw ResolutionError.missingService(id.name, id.file.path)
        }
        guard case .mapping(let serviceMap) = service else {
            throw ResolutionError.invalidReference(id.name)
        }

        var child = Node(serviceMap.filter { $0.key.string != "extends" }.map { ($0.key, $0.value) })
        if id.file != mainFile {
            child = rebasePaths(in: child, from: id.file.deletingLastPathComponent())
        }

        if let reference = serviceMap["extends"] {
            let parentName: String
            let parentFile: URL
            if let shorthand = reference.string {
                parentName = shorthand
                parentFile = id.file
            } else if case .mapping(let referenceMap) = reference,
                      let name = referenceMap["service"]?.string {
                parentName = name
                if let file = referenceMap["file"] {
                    guard let filename = file.string, !filename.isEmpty else {
                        throw ResolutionError.invalidReference(id.name)
                    }
                    parentFile = URL(fileURLWithPath: filename, relativeTo: mainFile.deletingLastPathComponent())
                        .standardizedFileURL.resolvingSymlinksInPath()
                } else {
                    parentFile = id.file
                }
            } else {
                throw ResolutionError.invalidReference(id.name)
            }
            guard !parentName.isEmpty else { throw ResolutionError.invalidReference(id.name) }
            let parent = try resolveService(ServiceID(file: parentFile, name: parentName), stack: stack + [id])
            if child["healthcheck"]?["disable"]?.bool == true,
               parent["healthcheck"]?["disable"]?.bool != true {
                throw ResolutionError.disabledHealthcheck(id.name)
            }
            child = merge(parent: parent, child: child)
        }
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

    private func merge(parent: Node, child: Node) -> Node {
        guard case .mapping(let parentMap) = parent,
              case .mapping(let childMap) = child else { return child }
        var result = parentMap
        for (key, value) in childMap {
            if let existing = result[key], let name = key.string {
                result[key] = mergeValue(parent: existing, child: value, path: name)
            } else {
                result[key] = value
            }
        }
        return .mapping(result)
    }

    private func mergeValue(parent: Node, child: Node, path: String) -> Node {
        if path == "environment", parent.sequence != nil || child.sequence != nil {
            let base = environmentMapping(parent)
            let override = environmentMapping(child)
            if let base, let override {
                return mergeValue(parent: base, child: override, path: path)
            }
        }

        if path == "volumes", case .sequence(let base) = parent,
           case .sequence(let override) = child {
            var items = Array(base)
            for item in override {
                if let target = volumeTarget(item),
                   let index = items.firstIndex(where: { volumeTarget($0) == target }) {
                    items[index] = item
                } else {
                    items.append(item)
                }
            }
            return Node(items)
        }

        if Self.mappingFields.contains(path),
           case .mapping(let base) = parent, case .mapping(let override) = child {
            var result = base
            for (key, value) in override {
                if let old = result[key], let name = key.string {
                    result[key] = mergeValue(parent: old, child: value, path: "\(path).\(name)")
                } else {
                    result[key] = value
                }
            }
            return .mapping(result)
        }

        if Self.uniqueSequences.contains(path),
           case .sequence(let base) = parent, case .sequence(let override) = child {
            var items = Array(base)
            for item in override where !items.contains(item) { items.append(item) }
            return Node(items)
        }
        if Self.duplicateSequences.contains(path) {
            let base = sequenceItems(parent)
            let override = sequenceItems(child)
            if let base, let override { return Node(base + override) }
        }
        return child
    }

    private func environmentMapping(_ node: Node) -> Node? {
        if case .mapping = node { return node }
        guard case .sequence(let entries) = node else { return nil }
        var pairs = [(Node, Node)]()
        for entry in entries {
            guard let string = entry.string else { return nil }
            let parts = string.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0])
            let value = parts.count == 2 ? String(parts[1]) : ProcessInfo.processInfo.environment[name] ?? ""
            pairs.append((Node(name), Node(value)))
        }
        return Node(pairs)
    }

    private func sequenceItems(_ node: Node) -> [Node]? {
        if case .sequence(let entries) = node { return Array(entries) }
        if case .scalar = node { return [node] }
        return nil
    }

    private static let mappingFields: Set<String> = [
        "annotations", "build", "build.args", "build.labels", "build.extra_hosts",
        "deploy", "deploy.labels", "deploy.update_config", "deploy.rollback_config",
        "deploy.restart_policy", "deploy.resources", "deploy.resources.limits",
        "environment", "healthcheck", "labels", "logging", "logging.options",
        "sysctls", "storage_opt", "extra_hosts", "ulimits",
    ]
    private static let uniqueSequences: Set<String> = [
        "cap_add", "cap_drop", "configs", "deploy.placement.constraints",
        "deploy.placement.preferences", "deploy.reservations.generic_resources",
        "device_cgroup_rules", "expose", "external_links", "ports", "secrets", "security_opt",
    ]
    private static let duplicateSequences: Set<String> = ["dns", "dns_search", "env_file", "tmpfs"]

    private func volumeTarget(_ node: Node) -> String? {
        if let target = node["target"]?.string { return target }
        guard let specification = node.string else { return nil }
        let parts = specification.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count > 1 ? String(parts[1]) : String(parts[0])
    }

    /// Keep paths inherited from another file anchored to that file. Runtime
    /// commands resolve relative paths against the main Compose directory.
    private func rebasePaths(in service: Node, from directory: URL) -> Node {
        var result = service
        if let envFile = result["env_file"] {
            if let filename = envFile.string {
                result["env_file"] = Node(absolutePath(filename, from: directory))
            } else if case .sequence(let entries) = envFile {
                result["env_file"] = Node(entries.map { entry in
                    if let filename = entry.string { return Node(absolutePath(filename, from: directory)) }
                    var mapped = entry
                    if let filename = mapped["path"]?.string {
                        mapped["path"] = Node(absolutePath(filename, from: directory))
                    }
                    return mapped
                })
            }
        }
        if let build = result["build"] {
            if let context = build.string {
                result["build"] = Node(absolutePath(context, from: directory))
            } else if let context = build["context"]?.string {
                var mapped = build
                mapped["context"] = Node(absolutePath(context, from: directory))
                result["build"] = mapped
            }
        }
        if let volumes = result["volumes"], case .sequence(let entries) = volumes {
            result["volumes"] = Node(entries.map { entry in
                guard let specification = entry.string else { return entry }
                let parts = specification.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, String(parts[0]).hasPrefix(".") else { return entry }
                return Node(absolutePath(String(parts[0]), from: directory) + ":" + parts[1])
            })
        }
        return result
    }

    private func absolutePath(_ path: String, from directory: URL) -> String {
        guard !path.hasPrefix("/"), !path.contains("://") else { return path }
        return URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL.path
    }
}
