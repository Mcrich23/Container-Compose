//
//  File.swift
//  Container-Compose
//
//  Created by Morris Richman on 6/18/25.
//

import Foundation
import Yams
import ArgumentParser

enum Action: String, ExpressibleByArgument, Codable {
    init?(argument: String) {
        self.init(rawValue: argument)
    }
    
    case up
}

@main
struct Application: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "container-compose",
        abstract: "A tool to use manage Docker Compose files with Apple Container"
        )
    
    @Argument(help: "Directs what container-compose should do")
    var action: Action
    
    @Flag(name: [.customShort("d"), .customLong("detach")])
    var detatch: Bool = false
    
    @Option(
        name: [.customLong("cwd"), .customShort("w"), .customLong("workdir")],
        help: "Current working directory for the container")
    public var cwd: String = FileManager.default.currentDirectoryPath
    
    var dockerComposePath: String { "\(cwd)/docker-compose.yml" } // Path to docker-compose.yml
    var envFilePath: String { "\(cwd)/.env" } // Path to optional .env file
//    
    private var fileManager: FileManager { FileManager.default }
    private var projectName: String?
    
    mutating func run() async throws {
        // Read docker-compose.yml content
        guard let yamlData = fileManager.contents(atPath: dockerComposePath) else {
            throw YamlError.dockerfileNotFound(dockerComposePath)
        }
        
        // Decode the YAML file into the DockerCompose struct
        let dockerComposeString = String(data: yamlData, encoding: .utf8)!
        let dockerCompose = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)
        
        // Load environment variables from .env file
        let envVarsFromFile = loadEnvFile(path: envFilePath)
        
        // Handle 'version' field
        if let version = dockerCompose.version {
            print("Info: Docker Compose file version parsed as: \(version)")
            print("Note: The 'version' field influences how a Docker Compose CLI interprets the file, but this custom 'container-compose' tool directly interprets the schema.")
        }

        // Determine project name for container naming
        if let name = dockerCompose.name {
            projectName = name
            print("Info: Docker Compose project name parsed as: \(name)")
            print("Note: The 'name' field currently only affects container naming (e.g., '\(name)-serviceName'). Full project-level isolation for other resources (networks, implicit volumes) is not implemented by this tool.")
        } else {
            projectName = URL(fileURLWithPath: cwd).lastPathComponent // Default to directory name
            print("Info: No 'name' field found in docker-compose.yml. Using directory name as project name: \(projectName)")
        }
        
        // Process top-level networks
        // This creates named networks defined in the docker-compose.yml
        if let networks = dockerCompose.networks {
            print("\n--- Processing Networks ---")
            for (networkName, networkConfig) in networks {
                try await setupNetwork(name: networkName, config: networkConfig)
            }
            print("--- Networks Processed ---\n")
        }
        
        // Process top-level volumes
        // This creates named volumes defined in the docker-compose.yml
        if let volumes = dockerCompose.volumes {
            print("\n--- Processing Volumes ---")
            for (volumeName, volumeConfig) in volumes {
                await createVolumeHardLink(name: volumeName, config: volumeConfig)
            }
            print("--- Volumes Processed ---\n")
        }
    }
    
    func createVolumeHardLink(name volumeName: String, config volumeConfig: Volume) async {
        guard let projectName else { return }
        let actualVolumeName = volumeConfig.name ?? volumeName // Use explicit name or key as name
        
        let volumeUrl = URL.homeDirectory.appending(path: ".containers/Volumes/\(projectName)/\(volumeName)")
        let volumePath = volumeUrl.path(percentEncoded: false)
        
        print("Warning: Volume source '\(volumeName)' appears to be a named volume reference. The 'container' tool does not support named volume references in 'container run -v' command. Linking to \(volumePath) instead.")
        try? fileManager.createDirectory(atPath: volumePath, withIntermediateDirectories: true)
    }
    
    func setupNetwork(name networkName: String, config networkConfig: Network) async throws {
        let actualNetworkName = networkConfig.name ?? networkName // Use explicit name or key as name

        if let externalNetwork = networkConfig.external, externalNetwork.isExternal {
            print("Info: Network '\(networkName)' is declared as external.")
            print("This tool assumes external network '\(externalNetwork.name ?? actualNetworkName)' already exists and will not attempt to create it.")
        } else {
            var networkCreateArgs: [String] = ["network", "create"]

            // Add driver and driver options
            if let driver = networkConfig.driver {
                networkCreateArgs.append("--driver")
                networkCreateArgs.append(driver)
            }
            if let driverOpts = networkConfig.driver_opts {
                for (optKey, optValue) in driverOpts {
                    networkCreateArgs.append("--opt")
                    networkCreateArgs.append("\(optKey)=\(optValue)")
                }
            }
            // Add various network flags
            if networkConfig.attachable == true { networkCreateArgs.append("--attachable") }
            if networkConfig.enable_ipv6 == true { networkCreateArgs.append("--ipv6") }
            if networkConfig.isInternal == true { networkCreateArgs.append("--internal") } // CORRECTED: Use isInternal
            
            // Add labels
            if let labels = networkConfig.labels {
                for (labelKey, labelValue) in labels {
                    networkCreateArgs.append("--label")
                    networkCreateArgs.append("\(labelKey)=\(labelValue)")
                }
            }

            networkCreateArgs.append(actualNetworkName) // Add the network name

            print("Creating network: \(networkName) (Actual name: \(actualNetworkName))")
            print("Executing container network create: container \(networkCreateArgs.joined(separator: " "))")
            let _ = try await runCommand("container", args: networkCreateArgs)
            #warning("Network creation output not used")
            print("Network '\(networkName)' created or already exists.")
        }
    }
}
