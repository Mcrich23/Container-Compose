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

/// Translates a Compose service's resource configuration into `container run`
/// flags shared by `up`, `run`, and `build`.
///
/// Compose expresses resources two ways — the service-level shorthands
/// (`cpus`, `mem_limit`, `mem_reservation`, `shm_size`, `tmpfs`, `ulimits`) and
/// the `deploy.resources` block. Both fold into Apple Container's limited flag
/// set; anything Apple Container cannot express (soft limits, device/GPU
/// reservations, replicas) is reported through `notes` instead of silently
/// dropped.
enum ResourceArguments {
    struct Result {
        var args: [String] = []
        var notes: [String] = []
    }

    static func runArgs(
        for service: Service,
        serviceName: String,
        environmentVariables: [String: String]
    ) -> Result {
        var result = Result()

        func resolve(_ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            return resolveVariable(value, with: environmentVariables)
        }

        // `deploy` is parsed but only its resource limits are usable for a
        // standalone container; say so once per service instead of listing
        // each unsupported field.
        if let deploy = service.deploy {
            let hasOrchestrationFields = deploy.mode != nil
                || deploy.replicas != nil
                || deploy.replicasExpression != nil
                || deploy.restart_policy != nil
            if hasOrchestrationFields {
                result.notes.append(
                    "Note: Service '\(serviceName)' defines 'deploy' orchestration fields (mode/replicas/restart_policy); "
                        + "this tool runs a single container and does not apply them."
                )
            }
        }

        // CPU limit: the official `deploy.resources.limits.cpus` wins over the
        // legacy service-level `cpus` shorthand, matching the Compose spec's
        // preference for the deploy form.
        let deployCpus = service.deploy?.resources?.limits?.cpus
        if deployCpus != nil, service.cpus != nil {
            result.notes.append(
                "Note: Service '\(serviceName)' sets both 'cpus' and 'deploy.resources.limits.cpus'; "
                    + "using the official deploy limit."
            )
        }
        // Apple Container's `--cpus` only takes whole CPUs, while Compose allows
        // fractional values (e.g. "1.5"), so round fractional requests up and say so.
        if let cpus = resolve(deployCpus ?? service.cpus) {
            if let value = Double(cpus) {
                if value.truncatingRemainder(dividingBy: 1) == 0 {
                    result.args.append(contentsOf: ["--cpus", "\(Int(value))"])
                } else {
                    let rounded = Int(value.rounded(.up))
                    result.args.append(contentsOf: ["--cpus", "\(rounded)"])
                    result.notes.append(
                        "Note: Service '\(serviceName)' requests \(cpus) CPUs; Apple Container only supports "
                            + "whole CPUs, rounding up to \(rounded)."
                    )
                }
            } else {
                result.args.append(contentsOf: ["--cpus", cpus])
            }
        }

        // Apple Container has no soft CPU reservation concept.
        if let reservedCpus = service.deploy?.resources?.reservations?.cpus {
            result.notes.append(
                "Note: Service '\(serviceName)' sets deploy.resources.reservations.cpus ('\(reservedCpus)'); "
                    + "Apple Container has no CPU reservation support; ignoring."
            )
        }

        // Memory: a hard limit wins; a lone reservation is approximated as the
        // hard `--memory` limit since Apple Container has no soft limit. The
        // official `deploy.resources` values win over the legacy shorthands.
        let deployLimitMemory = service.deploy?.resources?.limits?.memory
        if deployLimitMemory != nil, service.mem_limit != nil {
            result.notes.append(
                "Note: Service '\(serviceName)' sets both 'mem_limit' and 'deploy.resources.limits.memory'; "
                    + "using the official deploy limit."
            )
        }
        let limitMemory = resolve(deployLimitMemory ?? service.mem_limit)

        let deployReservedMemory = service.deploy?.resources?.reservations?.memory
        if deployReservedMemory != nil, service.mem_reservation != nil {
            result.notes.append(
                "Note: Service '\(serviceName)' sets both 'mem_reservation' and "
                    + "'deploy.resources.reservations.memory'; using the official deploy reservation."
            )
        }
        let reservedMemory = resolve(deployReservedMemory ?? service.mem_reservation)

        let effectiveMemory = limitMemory ?? reservedMemory
        if let effectiveMemory {
            let (memoryArg, didClamp) = ComposeUp.clampMemoryLimit(effectiveMemory)
            if didClamp {
                result.notes.append(
                    "Note: Service '\(serviceName)' memory '\(effectiveMemory)' is below Apple Container's "
                        + "200 MiB minimum; clamping to \(memoryArg)."
                )
            }
            if limitMemory == nil, reservedMemory != nil {
                result.notes.append(
                    "Note: Service '\(serviceName)' only sets a memory reservation; Apple Container has no soft "
                        + "memory limit, using it as the hard --memory limit."
                )
            }
            result.args.append(contentsOf: ["--memory", memoryArg])
        }
        if limitMemory != nil, reservedMemory != nil {
            result.notes.append(
                "Note: Service '\(serviceName)' sets a memory reservation alongside a hard limit; "
                    + "Apple Container has no soft memory limit; ignoring the reservation."
            )
        }

        // Apple Container has no device/GPU passthrough flags.
        if let reservedDevices = service.deploy?.resources?.reservations?.devices, !reservedDevices.isEmpty {
            result.notes.append(
                "Note: Service '\(serviceName)' reserves devices; Apple Container does not support "
                    + "device/GPU reservations; ignoring."
            )
        }
        if let devices = service.devices, !devices.isEmpty {
            result.notes.append(
                "Note: Service '\(serviceName)' maps devices; Apple Container does not support device "
                    + "mappings; ignoring."
            )
        }

        if let shmSize = resolve(service.shm_size) {
            result.args.append(contentsOf: ["--shm-size", shmSize])
        }

        for entry in service.tmpfs ?? [] {
            result.args.append(contentsOf: ["--tmpfs", resolve(entry) ?? entry])
        }

        for name in (service.ulimits ?? [:]).keys.sorted() {
            guard let ulimit = service.ulimits?[name] else { continue }
            guard let soft = resolve(ulimit.soft ?? ulimit.hard) else { continue }
            let hard = resolve(ulimit.hard ?? ulimit.soft)
            var formatted = "\(name)=\(soft)"
            if let hard, hard != soft {
                formatted += ":\(hard)"
            }
            result.args.append(contentsOf: ["--ulimit", formatted])
        }

        return result
    }
}
