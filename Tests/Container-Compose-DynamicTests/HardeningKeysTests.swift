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

import Testing
import Foundation
@testable import ContainerComposeCore

/// The hardening keys, asserted against what the kernel reports inside the
/// container rather than against the argv that was assembled.
///
/// Building the right `container run` flags and having them take effect are two
/// different claims; the static suite covers the first one. Everything here is
/// read from `/proc` inside a container that compose brought up.
@Suite("Hardening Keys - applied inside the container", .containerDependent, .serialized)
struct HardeningKeysTests {

    /// `CAP_NET_BIND_SERVICE` is capability 10, so a bounding set holding only it
    /// is `1 << 10`. Asserting the whole mask rather than "contains" is what makes
    /// `cap_drop: ALL` observable: anything left over shows up as extra bits.
    private static let expectedCapabilityMask: UInt64 = 1 << 10

    /// stdout arrives on an arbitrary queue, so it is accumulated behind a lock
    /// rather than into a captured `var`.
    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var text = ""
        func append(_ s: String) { lock.lock(); text += s; lock.unlock() }
        var value: String { lock.lock(); defer { lock.unlock() }; return text }
    }

    private func exec(_ container: String, _ script: String) async throws -> String {
        let output = Output()
        let compose = try ComposeUp.parse(["-d", "--cwd", NSTemporaryDirectory()])
        _ = try await compose.streamCommand(
            "container",
            args: ["exec", container, "sh", "-c", script],
            onStdout: { output.append($0) },
            onStderr: { _ in })
        return output.value
    }

    @Test("cap_drop, cap_add, tmpfs, shm_size, ulimits and init all take effect")
    func hardeningKeysAreApplied() async throws {
        let project = "hardening-\(UUID().uuidString.prefix(8).lowercased())"
        let dir = URL.temporaryDirectory.appending(path: project)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let yaml = """
        name: \(project)
        services:
          box:
            image: alpine:latest
            command: ["sleep", "300"]
            cap_drop: [ALL]
            cap_add: [NET_BIND_SERVICE]
            shm_size: 64M
            init: true
            ulimits:
              nofile:
                soft: 1234
                hard: 5678
            tmpfs:
              - /scratch
        """
        try yaml.write(to: dir.appending(path: "docker-compose.yaml"), atomically: false, encoding: .utf8)
        let box = "\(project)-box"

        func tearDown() async {
            var down = try? ComposeDown.parse(["--cwd", dir.path(percentEncoded: false)])
            try? await down?.run()
            _ = try? await ComposeUp.parse(["-d", "--cwd", dir.path(percentEncoded: false)])
                .streamCommand("container", args: ["delete", "-f", box],
                               onStdout: { _ in }, onStderr: { _ in })
            try? FileManager.default.removeItem(at: dir)
        }

        var composeUp = try ComposeUp.parse(["-d", "--cwd", dir.path(percentEncoded: false)])
        do {
            try await composeUp.run()

            // cap_drop: ALL then cap_add: one — the bounding set is the whole claim.
            let caps = try await exec(box, "grep '^CapBnd' /proc/self/status")
            let mask = caps.split(separator: ":").last
                .map { UInt64($0.trimmingCharacters(in: .whitespacesAndNewlines), radix: 16) } ?? nil
            #expect(mask == Self.expectedCapabilityMask,
                    "CapBnd was \(caps.trimmingCharacters(in: .whitespacesAndNewlines))")

            // tmpfs: the target is mounted, and mounted as tmpfs.
            let scratch = try await exec(box, "grep ' /scratch ' /proc/mounts")
            #expect(scratch.contains("tmpfs"), "/scratch mount line: \(scratch)")

            // shm_size: 64M reaches /dev/shm as size=65536k.
            let shm = try await exec(box, "grep ' /dev/shm ' /proc/mounts")
            #expect(shm.contains("size=65536k"), "/dev/shm mount line: \(shm)")

            // ulimits long form: soft and hard land in the right columns.
            let limits = try await exec(box, "grep -i 'open files' /proc/self/limits")
            let fields = limits.split(whereSeparator: \.isWhitespace)
            #expect(fields.contains("1234"), "limits line: \(limits)")
            #expect(fields.contains("5678"), "limits line: \(limits)")

            // init: PID 1 is the init shim, not the service command.
            let pid1 = try await exec(box, "cat /proc/1/comm")
            let comm = pid1.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(comm != "sleep", "PID 1 was \(comm); expected an init process")
            #expect(!comm.isEmpty)
        } catch {
            await tearDown()
            throw error
        }
        await tearDown()
    }
}
