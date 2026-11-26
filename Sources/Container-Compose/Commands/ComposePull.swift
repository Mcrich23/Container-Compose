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
//  ComposePull.swift
//  Container-Compose
//


import ArgumentParser
import ContainerAPIClient
import ContainerCommands
import Foundation
import TerminalProgress
import Yams

public struct ComposePull: AsyncParsableCommand {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "pull",
        abstract: "Pull images for services defined in a compose file"
    )

    @Argument(help: "Services to pull (pulls all if omitted)")
    var services: [String] = []

    @Flag(name: .long, help: "Also pull images for the services that requested services depend on")
    var includeDeps: Bool = false

    @OptionGroup
    var project: ComposeProjectOptions

    @OptionGroup
    var logging: Flags.Logging

    public mutating func run() async throws {
        let resolved = try project.resolve(filteringBy: services)

        // Fail fast on a typo'd/unknown service name — same contract #139
        // established for `up` ("no such service: <svc>").
        let defined: [(serviceName: String, service: Service)] = resolved.compose.services.compactMap { name, service in
            service.map { (name, $0) }
        }
        try Service.validateRequestedServices(services, against: defined)

        let targets = Self.pullTargets(in: resolved, requested: services, includeDeps: includeDeps)
        let (items, buildOnly) = Self.pullPlan(for: targets)
        for serviceName in buildOnly {
            // Build-only services have no image to pull; compose builds these.
            print("Skipping \(serviceName) (no image, built from a Dockerfile)")
        }
        guard !items.isEmpty else { return }

        let display = PullProgressDisplay(labels: items.map(\.label), interactive: isatty(STDOUT_FILENO) == 1)
        await display.start()

        await withTaskGroup(of: Void.self) { group in
            var remaining = items.enumerated().makeIterator()

            func startNext() {
                guard let (index, item) = remaining.next() else { return }
                group.addTask {
                    do {
                        try await Self.pull(item) { await display.update(index, $0) }
                        await display.finish(index, error: nil)
                    } catch {
                        await display.finish(index, error: error)
                    }
                }
            }

            for _ in 0..<Self.maxConcurrentPulls { startNext() }
            for await _ in group { startNext() }
        }
        if await display.hasFailures {
            throw ExitCode.failure
        }
    }

    /// The services `pull` acts on. The shared selection expands `depends_on`
    /// (which `up` needs to start dependencies), but `docker compose pull
    /// <svc>` pulls only the named services unless `--include-deps` is passed —
    /// so explicit requests are narrowed back to the requested names.
    static func pullTargets(
        in project: ComposeProject,
        requested: [String],
        includeDeps: Bool
    ) -> [ComposeProject.ServiceTarget] {
        guard !requested.isEmpty, !includeDeps else { return project.services }
        return project.services.filter { requested.contains($0.serviceName) }
    }

    /// The image reference to pull for a service, with `${VAR}` /
    /// `${VAR:-default}` placeholders resolved from the environment file —
    /// a literal `${...}` is not a valid registry reference. `nil` for
    /// build-only services (no `image:` key).
    static func resolvedImage(for service: Service, environment: [String: String]) -> String? {
        service.image.map { resolveVariable($0, with: environment) }
    }

    /// Maximum simultaneous pulls. Each pull downloads up to three layers at
    /// once, so this bounds total registry connections.
    static let maxConcurrentPulls = 3

    /// One deduplicated pull and the services that use it.
    struct PullItem: Equatable, Sendable {
        let image: String
        let platform: String?
        var services: [String]

        var label: String { "\(services.joined(separator: ", ")) (\(image))" }
    }

    /// Groups targets into pull items, one per distinct image and platform, in
    /// service order.
    ///
    /// - Returns: The pull items, and the build-only services (no `image:`).
    static func pullPlan(for targets: [ComposeProject.ServiceTarget]) -> (items: [PullItem], buildOnly: [String]) {
        var items: [PullItem] = []
        var buildOnly: [String] = []
        var indexByKey: [String: Int] = [:]

        for target in targets {
            guard let image = target.service.image else {
                buildOnly.append(target.serviceName)
                continue
            }
            let platform = target.service.effectivePullPlatform()
            let key = "\(image)|\(platform ?? "")"
            if let index = indexByKey[key] {
                items[index].services.append(target.serviceName)
            } else {
                indexByKey[key] = items.count
                items.append(PullItem(image: image, platform: platform, services: [target.serviceName]))
            }
        }
        return (items, buildOnly)
    }

    /// Pulls and unpacks one image, reporting progress. Always pulls, even when
    /// the image exists locally: refreshing a moving tag like `:latest` is the
    /// point of an explicit `pull`.
    ///
    /// Calls the client API directly rather than `container image pull`, whose
    /// single-line progress bar can't share the terminal with concurrent pulls.
    private static func pull(
        _ item: PullItem,
        progress: @escaping @Sendable (PullProgressDisplay.Update) async -> Void
    ) async throws {
        let config = try await ClientHealthCheck.loadContainerSystemConfig()
        let platform = try DefaultPlatform.resolve(platform: item.platform, os: nil, arch: nil)

        await progress(.phase("Fetching"))
        let image = try await ClientImage.pull(
            reference: item.image, platform: platform, scheme: .https, containerSystemConfig: config,
            progressUpdate: { await progress(.events($0)) })

        await progress(.phase("Unpacking"))
        try await image.unpack(platform: platform, progressUpdate: { await progress(.events($0)) })
    }
}

/// Renders one progress line per concurrent pull. On a terminal the lines are
/// redrawn in place; otherwise only start and finish lines are printed.
actor PullProgressDisplay {
    enum Update: Sendable {
        case phase(String)
        case events([ProgressUpdateEvent])
    }

    struct Line {
        var label: String
        var phase = "Waiting"
        var size: Int64 = 0
        var totalSize: Int64 = 0
        var items = 0
        var totalItems = 0
        var done = false
        var error: String?
    }

    private var lines: [Line]
    private let interactive: Bool
    private var lastDraw = Date.distantPast
    private(set) var hasFailures = false

    init(labels: [String], interactive: Bool) {
        self.lines = labels.map { Line(label: $0) }
        self.interactive = interactive
    }

    func start() {
        guard interactive else { return }
        for line in lines { print(Self.render(line)) }
        fflush(stdout)
    }

    func update(_ index: Int, _ update: Update) {
        switch update {
        case .phase(let phase):
            if !interactive && phase == "Fetching" { print("Pulling \(lines[index].label)...") }
            lines[index].phase = phase
            lines[index].size = 0
            lines[index].totalSize = 0
            lines[index].items = 0
            lines[index].totalItems = 0
            draw(force: true)
        case .events(let events):
            for event in events { Self.apply(event, to: &lines[index]) }
            draw(force: false)
        }
    }

    func finish(_ index: Int, error: Error?) {
        lines[index].done = true
        if let error {
            lines[index].error = String(describing: error)
            hasFailures = true
        }
        if interactive {
            draw(force: true)
        } else if let message = lines[index].error {
            print("Error pulling \(lines[index].label): \(message)")
        } else {
            print("Pulled \(lines[index].label)")
        }
    }

    static func apply(_ event: ProgressUpdateEvent, to line: inout Line) {
        switch event {
        case .addSize(let n): line.size += n
        case .setSize(let n): line.size = n
        case .addTotalSize(let n): line.totalSize += n
        case .setTotalSize(let n): line.totalSize = n
        case .addItems(let n): line.items += n
        case .setItems(let n): line.items = n
        case .addTotalItems(let n): line.totalItems += n
        case .setTotalItems(let n): line.totalItems = n
        default: break
        }
    }

    /// Redraws every line in place, at most ten times a second unless forced.
    private func draw(force: Bool) {
        guard interactive else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastDraw) >= 0.1 else { return }
        lastDraw = now
        var out = "\u{1B}[\(lines.count)A"
        for line in lines { out += "\u{1B}[2K" + Self.render(line) + "\n" }
        FileHandle.standardOutput.write(Data(out.utf8))
    }

    static func render(_ line: Line) -> String {
        if let error = line.error { return "\(line.label)  failed: \(error)" }
        if line.done { return "\(line.label)  done" }

        let fraction: Double?
        let detail: String
        if line.totalSize > 0 {
            fraction = Double(line.size) / Double(line.totalSize)
            detail = "\(Self.bytes(line.size)) / \(Self.bytes(line.totalSize))"
        } else if line.totalItems > 0 {
            fraction = Double(line.items) / Double(line.totalItems)
            detail = "\(line.items) / \(line.totalItems)"
        } else {
            fraction = nil
            detail = ""
        }
        guard let fraction else { return "\(line.label)  \(line.phase)" }
        let clamped = min(max(fraction, 0), 1)
        let width = 20
        let filled = Int(clamped * Double(width))
        let bar = String(repeating: "=", count: filled) + String(repeating: " ", count: width - filled)
        return "\(line.label)  \(line.phase) [\(bar)] \(Int(clamped * 100))% \(detail)"
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
