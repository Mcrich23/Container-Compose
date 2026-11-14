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
//  ComposeImages.swift
//  Container-Compose
//
//  Implements the `images` subcommand, which lists the images backing a
//  compose project's services.
//

import ArgumentParser
import ContainerCommands
import ContainerAPIClient
import Foundation
import Yams

public struct ComposeImages: AsyncParsableCommand {
    public init() {}

    public static let configuration: CommandConfiguration = .init(
        commandName: "images",
        abstract: "List images used by this compose project's services"
    )

    @Argument(help: "Specify the services to list")
    var services: [String] = []

    @OptionGroup
    var project: ComposeProjectOptions

    public func run() async throws {
        let resolved = try project.resolve(filteringBy: services)
        try ComposePs.validateRequestedServices(services, in: resolved)

        // Best-effort cross reference of locally available images so we can
        // surface IMAGE ID / SIZE when the image has already been pulled/built.
        let localImages = (try? await ClientImage.list()) ?? []

        let header = ["SERVICE", "REPOSITORY", "TAG", "IMAGE ID", "SIZE"]
        var rows: [[String]] = []

        for target in resolved.services {
            // Build-only services with no explicit `image` are tagged
            // `<service>:latest` by `up`/`build`, mirroring that here.
            let imageRef = target.service.image ?? "\(target.serviceName):latest"
            let (repository, tag) = Self.splitReference(imageRef)

            let match = Self.matchingImage(for: imageRef, in: localImages)
            let imageID = match.map { Self.shortDigest($0.description.digest) } ?? ""
            var size = ""
            if let match, let bytes = try? await ClientImage.getFullImageSize(image: match) {
                size = Self.humanReadableSize(bytes)
            }

            rows.append([target.serviceName, repository, tag, imageID, size])
        }

        print(TableFormatter.render(header: header, rows: rows))
    }

    /// Splits an image reference on the last `:`, treating a colon followed
    /// by a `/` as a registry host:port separator rather than a tag.
    ///
    /// - Returns: The repository and tag; the tag is `"latest"` when the
    ///   reference carries none.
    static func splitReference(_ reference: String) -> (repository: String, tag: String) {
        guard let colonIndex = reference.lastIndex(of: ":") else {
            return (reference, "latest")
        }
        let tag = String(reference[reference.index(after: colonIndex)...])
        // A `/` after the colon means the colon was a host:port separator, not a tag.
        if tag.contains("/") {
            return (reference, "latest")
        }
        return (String(reference[..<colonIndex]), tag)
    }

    /// Finds a locally available image whose stored reference matches
    /// `imageRef` exactly, with a registry prefix, or by its last path
    /// component (short references) — the same match rule `up` uses to
    /// decide whether a pull is needed.
    ///
    /// - Returns: The first matching image, or `nil` when none is local.
    static func matchingImage(for imageRef: String, in images: [ClientImage]) -> ClientImage? {
        images.first { image in
            let stored = image.description.reference
            return stored == imageRef
                || stored.hasSuffix("/\(imageRef)")
                || stored.components(separatedBy: "/").last == imageRef
        }
    }

    /// Shortens a digest like `sha256:<hex>` to its leading 12 hex characters,
    /// the conventional short image ID.
    static func shortDigest(_ digest: String) -> String {
        let hex = digest.split(separator: ":").last.map(String.init) ?? digest
        return String(hex.prefix(12))
    }

    /// Formats a byte count with binary units (B, KB, MB, …), one decimal
    /// place below 10, and an empty string for zero or negative sizes so the
    /// table cell stays blank when the size is unknown.
    static func humanReadableSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return String(format: value < 10 && unit > 0 ? "%.1f %@" : "%.0f %@", value, units[unit])
    }
}
