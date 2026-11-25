import ContainerAPIClient
import ContainerResource

/// Shares resource names and ownership rules between creation and teardown.
enum ComposeResources {
    static let ownerKey = "io.container-compose.managed"
    static let projectKey = "com.docker.compose.project"

    static func labels(project: String, existing: [String: String] = [:]) -> [String: String] {
        var labels = existing
        labels[ownerKey] = "true"
        labels[projectKey] = project
        return labels
    }

    static func owns(_ labels: [String: String], project: String) -> Bool {
        labels[ownerKey] == "true" && labels[projectKey] == project
    }

    static func networkName(_ key: String, config: Network?, project: String) -> String {
        if config?.external?.isExternal == true {
            return config?.external?.name ?? config?.name ?? key
        }
        return config?.name ?? "\(project)_\(key)".lowercased()
    }

    static func cleanup(project: ComposeProject, volumes: Bool) async throws {
        let survivors = try await ContainerClient().list()
        let attachedNetworks = Set(survivors.flatMap { $0.configuration.networks.map(\.network) })
        let attachedVolumes = Set(survivors.flatMap { container in
            container.configuration.mounts.compactMap { mount -> String? in
                if case .volume(let name, _, _, _) = mount.type { return name }
                return nil
            }
        })
        let mountSources = Set(survivors.flatMap { $0.configuration.mounts.map(\.source) })
        let externalNetworks = Set((project.compose.networks ?? [:]).compactMap { key, config -> String? in
            guard config?.external?.isExternal == true else { return nil }
            return networkName(key, config: config, project: project.projectName)
        })
        let networkClient = NetworkClient()
        for network in try await networkClient.list() {
            guard !network.isBuiltin, network.id != NetworkClient.defaultNetworkName,
                  !externalNetworks.contains(network.id), !attachedNetworks.contains(network.id) else { continue }
            guard owns(network.configuration.labels.dictionary, project: project.projectName) else {
                if network.id.hasPrefix(project.projectName + "_") || project.compose.networks?[network.id] != nil {
                    print("Preserving network '\(network.id)': ownership is unproven.")
                }
                continue
            }
            try await networkClient.delete(id: network.id)
        }
        guard volumes else { return }
        let externalVolumes = Set((project.compose.volumes ?? [:]).compactMap { key, config -> String? in
            guard config?.external?.isExternal == true else { return nil }
            return composeNamedVolumeName(source: key, projectName: project.projectName, volumeDefinition: config)
        })
        let configuredVolumes = Set((project.compose.volumes ?? [:]).map { key, config in
            composeNamedVolumeName(source: key, projectName: project.projectName, volumeDefinition: config)
        })
        for volume in try await ClientVolume.list() {
            guard !externalVolumes.contains(volume.name), !attachedVolumes.contains(volume.name), !mountSources.contains(volume.source) else { continue }
            guard owns(volume.labels, project: project.projectName) else {
                if volume.name.hasPrefix(project.projectName + "_") || configuredVolumes.contains(volume.name) {
                    print("Preserving volume '\(volume.name)': ownership is unproven.")
                }
                continue
            }
            try await ClientVolume.delete(name: volume.name)
        }
    }
}
