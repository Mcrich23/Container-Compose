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
import ContainerCommands
import ContainerAPIClient
import Foundation
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

        let environment = loadEnvFile(path: project.envFilePath)

        let targets = Self.pullTargets(in: resolved, requested: services, includeDeps: includeDeps)
        let (items, buildOnly) = Self.pullPlan(for: targets, environment: environment)
        for serviceName in buildOnly {
            // Build-only services have no image to pull; compose builds these.
            print("Skipping \(serviceName) (no image, built from a Dockerfile)")
        }
        guard !items.isEmpty else { return }

        // Pull a bounded number of images concurrently. With more than one
        // pull in flight, per-pull progress rendering is disabled (interleaved
        // progress bars are unreadable) and our own start/finish lines report
        // instead; a single pull keeps the full progress output.
        let passThrough = logging.passThroughCommands()
        let parallel = items.count > 1
        var failedImages: [String] = []

        try await withThrowingTaskGroup(of: (image: String, error: Error?).self) { group in
            var remaining = items.makeIterator()

            @discardableResult
            func startNext() -> Bool {
                guard let item = remaining.next() else { return false }
                print("Pulling \(item.services.joined(separator: ", ")) (\(item.image))...")
                group.addTask {
                    do {
                        try await Self.pull(item, passThrough: passThrough, quietProgress: parallel)
                        return (item.image, nil)
                    } catch {
                        return (item.image, error)
                    }
                }
                return true
            }

            for _ in 0..<Self.maxConcurrentPulls {
                guard startNext() else { break }
            }
            while let (image, error) = try await group.next() {
                if let error {
                    failedImages.append(image)
                    print("Error pulling \(image): \(error)")
                } else if parallel {
                    print("Pulled \(image)")
                }
                startNext()
            }
        }

        if !failedImages.isEmpty {
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

    /// Maximum simultaneous `container image pull` operations. Each pull
    /// already downloads up to three layers concurrently, so a modest cap
    /// keeps the total number of registry connections reasonable.
    static let maxConcurrentPulls = 3

    /// One deduplicated pull: an image reference (variables resolved), the
    /// platform to pull it for, and the services that use it.
    struct PullItem: Equatable, Sendable {
        let image: String
        let platform: String?
        var services: [String]
    }

    /// Groups the targets into deduplicated pull items, preserving service
    /// order: services that share an image and platform pull it once.
    ///
    /// - Returns: The pull items, and the names of build-only services
    ///   (no `image:` key) so the caller can report them as skipped.
    static func pullPlan(
        for targets: [ComposeProject.ServiceTarget],
        environment: [String: String]
    ) -> (items: [PullItem], buildOnly: [String]) {
        var items: [PullItem] = []
        var buildOnly: [String] = []
        var indexByKey: [String: Int] = [:]

        for target in targets {
            guard let image = resolvedImage(for: target.service, environment: environment) else {
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

    /// Pulls one image. Always pulls, even when a matching image exists
    /// locally: refreshing a moving tag like `:latest` is the point of an
    /// explicit `pull` (`up`'s implicit pull keeps the already-present
    /// shortcut).
    private static func pull(_ item: PullItem, passThrough: [String], quietProgress: Bool) async throws {
        var commands = [item.image]
        if let platform = item.platform {
            commands.append(contentsOf: ["--platform", platform])
        }
        if quietProgress {
            commands.append(contentsOf: ["--progress", "none"])
        }

        let imagePull = try Application.ImagePull.parse(commands + passThrough)
        try await imagePull.run()
    }
}
