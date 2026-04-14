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

struct NormalizedVolumeConfiguration: Equatable {
    let driver: String
    let driverOpts: [String: String]
}

enum VolumeConfigurationNormalizer {
    static func normalized(from volumeConfig: Volume) -> NormalizedVolumeConfiguration {
        let driver = volumeConfig.driver ?? "local"
        let driverOpts = volumeConfig.driver_opts ?? [:]

        guard driver == "local", let type = driverOpts["type"]?.lowercased() else {
            return NormalizedVolumeConfiguration(driver: driver, driverOpts: driverOpts)
        }

        switch type {
        case "cifs", "smb":
            return NormalizedVolumeConfiguration(driver: "smb", driverOpts: normalizeNetworkDriverOptions(driverOpts))
        case "nfs":
            return NormalizedVolumeConfiguration(driver: "nfs", driverOpts: normalizeNetworkDriverOptions(driverOpts))
        default:
            return NormalizedVolumeConfiguration(driver: driver, driverOpts: driverOpts)
        }
    }

    private static func normalizeNetworkDriverOptions(_ driverOpts: [String: String]) -> [String: String] {
        var normalized = driverOpts

        if let device = normalized.removeValue(forKey: "device") {
            normalized["share"] = device
        }

        if let optionString = normalized.removeValue(forKey: "o") {
            for rawOption in optionString.split(separator: ",").map(String.init) where !rawOption.isEmpty {
                let parts = rawOption.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    normalized[parts[0]] = parts[1]
                } else {
                    normalized[rawOption] = ""
                }
            }
        }

        normalized.removeValue(forKey: "type")
        return normalized
    }
}
