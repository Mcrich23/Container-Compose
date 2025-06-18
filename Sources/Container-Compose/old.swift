import Foundation
import Yams

//// MARK: - Main Logic
//let usageString = "Usage: container-compose up [-d]"
//
//// Process command line arguments
//let arguments = CommandLine.arguments
//guard arguments.count >= 2 else {
//    print(usageString)
//    exit(1)
//}
//
//let subcommand = arguments[1] // Get the subcommand (e.g., "up")
//let detachFlag = arguments.contains("-d") // Check for the -d (detach) flag
//
//// Currently, only the "up" subcommand is supported
//guard subcommand == "up" else {
//    print("Error: Only 'up' subcommand is supported.")
//    exit(1)
//}
//
//let fileManager = FileManager.default
//let currentDirectory = "/Users/mcrich/Xcode/Assignment-Manager-API" //fileManager.currentDirectoryPath // Get current working directory
//let dockerComposePath = "\(currentDirectory)/docker-compose.yml" // Path to docker-compose.yml
//let envFilePath = "\(currentDirectory)/.env" // Path to optional .env file
//
//// Read docker-compose.yml content
//guard let yamlData = fileManager.contents(atPath: dockerComposePath) else {
//    fputs("Error: docker-compose.yml not found at \(dockerComposePath)\n", stderr)
//    exit(1)
//}
//
//do {
//    // Decode the YAML file into the DockerCompose struct
//    let dockerComposeString = String(data: yamlData, encoding: .utf8)!
//    let dockerCompose = try YAMLDecoder().decode(DockerCompose.self, from: dockerComposeString)
//
//    // Load environment variables from .env file
//    let envVarsFromFile = loadEnvFile(path: envFilePath)
//
//    // Handle 'version' field
//    if let version = dockerCompose.version {
//        print("Info: Docker Compose file version parsed as: \(version)")
//        print("Note: The 'version' field influences how a Docker Compose CLI interprets the file, but this custom 'container-compose' tool directly interprets the schema.")
//    }
//
//    // Determine project name for container naming
//    let projectName: String
//    if let name = dockerCompose.name {
//        projectName = name
//        print("Info: Docker Compose project name parsed as: \(name)")
//        print("Note: The 'name' field currently only affects container naming (e.g., '\(name)-serviceName'). Full project-level isolation for other resources (networks, implicit volumes) is not implemented by this tool.")
//    } else {
//        projectName = URL(fileURLWithPath: currentDirectory).lastPathComponent // Default to directory name
//        print("Info: No 'name' field found in docker-compose.yml. Using directory name as project name: \(projectName ?? "unknown")")
//    }
//
//    // Process top-level networks
//    // This creates named networks defined in the docker-compose.yml
//    if let networks = dockerCompose.networks {
//        print("\n--- Processing Networks ---")
//        for (networkName, networkConfig) in networks {
//            let actualNetworkName = networkConfig.name ?? networkName // Use explicit name or key as name
//
//            if let externalNetwork = networkConfig.external, externalNetwork.isExternal {
//                print("Info: Network '\(networkName)' is declared as external.")
//                print("This tool assumes external network '\(externalNetwork.name ?? actualNetworkName)' already exists and will not attempt to create it.")
//            } else {
//                var networkCreateArgs: [String] = ["network", "create"]
//
//                // Add driver and driver options
//                if let driver = networkConfig.driver {
//                    networkCreateArgs.append("--driver")
//                    networkCreateArgs.append(driver)
//                }
//                if let driverOpts = networkConfig.driver_opts {
//                    for (optKey, optValue) in driverOpts {
//                        networkCreateArgs.append("--opt")
//                        networkCreateArgs.append("\(optKey)=\(optValue)")
//                    }
//                }
//                // Add various network flags
//                if networkConfig.attachable == true { networkCreateArgs.append("--attachable") }
//                if networkConfig.enable_ipv6 == true { networkCreateArgs.append("--ipv6") }
//                if networkConfig.isInternal == true { networkCreateArgs.append("--internal") } // CORRECTED: Use isInternal
//                
//                // Add labels
//                if let labels = networkConfig.labels {
//                    for (labelKey, labelValue) in labels {
//                        networkCreateArgs.append("--label")
//                        networkCreateArgs.append("\(labelKey)=\(labelValue)")
//                    }
//                }
//
//                networkCreateArgs.append(actualNetworkName) // Add the network name
//
//                print("Creating network: \(networkName) (Actual name: \(actualNetworkName))")
//                print("Executing container network create: container \(networkCreateArgs.joined(separator: " "))")
//                executeCommand(command: "container", arguments: networkCreateArgs, detach: false)
//                print("Network '\(networkName)' created or already exists.")
//            }
//        }
//        print("--- Networks Processed ---\n")
//    }
//
//    // Process top-level volumes
//    // This creates named volumes defined in the docker-compose.yml
//    if let volumes = dockerCompose.volumes {
//        print("\n--- Processing Volumes ---")
//        for (volumeName, volumeConfig) in volumes {
//            let actualVolumeName = volumeConfig.name ?? volumeName // Use explicit name or key as name
//
////            if let externalVolume = volumeConfig.external, externalVolume.isExternal {
////                print("Info: Volume '\(volumeName)' is declared as external.")
////                print("This tool assumes external volume '\(externalVolume.name ?? actualVolumeName)' already exists and will not attempt to create it.")
////            } else {
////                var volumeCreateArgs: [String] = ["volume", "create"]
////
////                // Add driver and driver options
////                if let driver = volumeConfig.driver {
////                    volumeCreateArgs.append("--driver")
////                    volumeCreateArgs.append(driver)
////                }
////                if let driverOpts = volumeConfig.driver_opts {
////                    for (optKey, optValue) in driverOpts {
////                        volumeCreateArgs.append("--opt")
////                        volumeCreateArgs.append("\(optKey)=\(optValue)")
////                    }
////                }
////                // Add labels
////                if let labels = volumeConfig.labels {
////                    for (labelKey, labelValue) in labels {
////                        volumeCreateArgs.append("--label")
////                        volumeCreateArgs.append("\(labelKey)=\(labelValue)")
////                    }
////                }
////
////                volumeCreateArgs.append(actualVolumeName) // Add the volume name
////
////                print("Creating volume: \(volumeName) (Actual name: \(actualVolumeName))")
////                print("Executing container volume create: container \(volumeCreateArgs.joined(separator: " "))")
////                executeCommand(command: "container", arguments: volumeCreateArgs, detach: false)
////                print("Volume '\(volumeName)' created or already exists.")
////            }
//            let volumeUrl = URL.homeDirectory.appending(path: ".containers/Volumes/\(projectName)/\(volumeName)")
//            let volumePath = volumeUrl.path(percentEncoded: false)
//            
//            print("Warning: Volume source '\(volumeName)' appears to be a named volume reference. The 'container' tool does not support named volume references in 'container run -v' command. Linking to \(volumePath) instead.")
//            try? fileManager.createDirectory(atPath: volumePath, withIntermediateDirectories: true)
//        }
//        print("--- Volumes Processed ---\n")
//    }
//
//    // Process top-level configs
//    // Note: Docker Compose 'configs' are primarily for Docker Swarm and are not directly managed by 'container run'.
//    // The tool parses them but does not create or attach them.
//    if let configs = dockerCompose.configs {
//        print("\n--- Processing Configs ---")
//        print("Note: Docker Compose 'configs' are primarily used for Docker Swarm deployed stacks and are not directly translatable to 'container run' commands.")
//        print("This tool will parse 'configs' definitions but will not create or attach them to containers.")
//        for (configName, configConfig) in configs {
//            let actualConfigName = configConfig.name ?? configName
//            if let externalConfig = configConfig.external, externalConfig.isExternal {
//                print("Info: Config '\(configName)' is declared as external (actual name: \(externalConfig.name ?? actualConfigName)). This tool will not attempt to create or manage it.")
//            } else if let file = configConfig.file {
//                let resolvedFile = resolveVariable(file, with: envVarsFromFile)
//                print("Info: Config '\(configName)' is defined from file '\(resolvedFile)'. This tool cannot automatically manage its distribution to individual containers outside of Swarm mode.")
//            } else {
//                print("Info: Config '\(configName)' (actual name: \(actualConfigName)) is defined. This tool cannot automatically manage its distribution to individual containers outside of Swarm mode.")
//            }
//        }
//        print("--- Configs Processed ---\n")
//    }
//    
//    // Process top-level secrets
//    // Note: Docker Compose 'secrets' are primarily for Docker Swarm and are not directly managed by 'container run'.
//    // The tool parses them but does not create or attach them.
//    if let secrets = dockerCompose.secrets {
//        print("\n--- Processing Secrets ---")
//        print("Note: Docker Compose 'secrets' are primarily used for Docker Swarm deployed stacks and are not directly translatable to 'container run' commands.")
//        print("This tool will parse 'secrets' definitions but will not create or attach them to containers.")
//        for (secretName, secretConfig) in secrets {
//            let actualSecretName = secretConfig.name ?? secretName // Define actualSecretName here
//            if let externalSecret = secretConfig.external, externalSecret.isExternal {
//                print("Info: Secret '\(secretName)' is declared as external (actual name: \(externalSecret.name ?? actualSecretName)). This tool will not attempt to create or manage it.")
//            } else if let file = secretConfig.file {
//                let resolvedFile = resolveVariable(file, with: envVarsFromFile)
//                print("Info: Secret '\(secretName)' is defined from file '\(resolvedFile)'. This tool cannot automatically manage its distribution to individual containers outside of Swarm mode.")
//            } else {
//                print("Info: Secret '\(secretName)' (actual name: \(actualSecretName)) is defined. This tool cannot automatically manage its distribution to individual containers outside of Swarm mode.")
//            }
//        }
//        print("--- Secrets Processed ---\n")
//    }
//
//
//    // Process each service defined in the docker-compose.yml
//    print("\n--- Processing Services ---")
//    for (serviceName, service) in dockerCompose.services {
//        var imageToRun: String
//
//        // Handle 'build' configuration
//        if let buildConfig = service.build {
//            var buildCommandArgs: [String] = ["build"]
//
//            // Determine image tag for built image
//            imageToRun = service.image ?? "\(serviceName):latest"
//
//            buildCommandArgs.append("--tag")
//            buildCommandArgs.append(imageToRun)
//
//            // Resolve build context path
//            let resolvedContext = resolveVariable(buildConfig.context, with: envVarsFromFile)
//            buildCommandArgs.append(resolvedContext)
//
//            // Add Dockerfile path if specified
//            if let dockerfile = buildConfig.dockerfile {
//                let resolvedDockerfile = resolveVariable(dockerfile, with: envVarsFromFile)
//                buildCommandArgs.append("--file")
//                buildCommandArgs.append(resolvedDockerfile)
//            }
//
//            // Add build arguments
//            if let args = buildConfig.args {
//                for (key, value) in args {
//                    let resolvedValue = resolveVariable(value, with: envVarsFromFile)
//                    buildCommandArgs.append("--build-arg")
//                    buildCommandArgs.append("\(key)=\(resolvedValue)")
//                }
//            }
//            
//            print("\n----------------------------------------")
//            print("Building image for service: \(serviceName) (Tag: \(imageToRun))")
//            print("Executing container build: container \(buildCommandArgs.joined(separator: " "))")
//            executeCommand(command: "container", arguments: buildCommandArgs, detach: false)
//            print("Image build for \(serviceName) completed.")
//            print("----------------------------------------")
//
//        } else if let img = service.image {
//            // Use specified image if no build config
//            imageToRun = resolveVariable(img, with: envVarsFromFile)
//        } else {
//            // Should not happen due to Service init validation, but as a fallback
//            fputs("Error: Service \(serviceName) must define either 'image' or 'build'. Skipping.\n", stderr)
//            continue
//        }
//
//        // Handle 'deploy' configuration (note that this tool doesn't fully support it)
//        if service.deploy != nil {
//            print("Note: The 'deploy' configuration for service '\(serviceName)' was parsed successfully.")
//            print("However, this 'container-compose' tool does not currently support 'deploy' functionality (e.g., replicas, resources, update strategies) as it is primarily for orchestration platforms like Docker Swarm or Kubernetes, not direct 'container run' commands.")
//            print("The service will be run as a single container based on other configurations.")
//        }
//
//        var runCommandArgs: [String] = []
//
//        // Add detach flag if specified on the CLI
//        if detachFlag {
//            runCommandArgs.append("-d")
//        }
//
//        // Determine container name
//        let containerName: String
//        if let explicitContainerName = service.container_name {
//            containerName = explicitContainerName
//            print("Info: Using explicit container_name: \(containerName)")
//        } else {
//            // Default container name based on project and service name
//            containerName = "\(projectName)-\(serviceName)"
//        }
//        runCommandArgs.append("--name")
//        runCommandArgs.append(containerName)
//
//        // REMOVED: Restart policy is not supported by `container run`
//        // if let restart = service.restart {
//        //     runCommandArgs.append("--restart")
//        //     runCommandArgs.append(restart)
//        // }
//
//        // Add user
//        if let user = service.user {
//            runCommandArgs.append("--user")
//            runCommandArgs.append(user)
//        }
//
//        // Add volume mounts
//        if let volumes = service.volumes {
//            for volume in volumes {
//                let resolvedVolume = resolveVariable(volume, with: envVarsFromFile)
//                
//                // Parse the volume string: destination[:mode]
//                let components = resolvedVolume.split(separator: ":", maxSplits: 2).map(String.init)
//                
//                guard components.count >= 2 else {
//                    print("Warning: Volume entry '\(resolvedVolume)' has an invalid format (expected 'source:destination'). Skipping.")
//                    continue
//                }
//
//                let source = components[0]
//                let destination = components[1]
//                
//                // Check if the source looks like a host path (contains '/' or starts with '.')
//                // This heuristic helps distinguish bind mounts from named volume references.
//                if source.contains("/") || source.starts(with: ".") || source.starts(with: "..") {
//                    // This is likely a bind mount (local path to container path)
//                    var isDirectory: ObjCBool = false
//                    // Ensure the path is absolute or relative to the current directory for FileManager
//                    let fullHostPath = (source.starts(with: "/") || source.starts(with: "~")) ? source : (currentDirectory + "/" + source)
//                    
//                    if fileManager.fileExists(atPath: fullHostPath, isDirectory: &isDirectory) {
//                        if isDirectory.boolValue {
//                            // Host path exists and is a directory, add the volume
//                            runCommandArgs.append("-v")
//                            // Reconstruct the volume string without mode, ensuring it's source:destination
//                            runCommandArgs.append("\(source):\(destination)") // Use original source for command argument
//                        } else {
//                            // Host path exists but is a file
//                            print("Warning: Volume mount source '\(source)' is a file. The 'container' tool does not support direct file mounts. Skipping this volume.")
//                        }
//                    } else {
//                        // Host path does not exist, assume it's meant to be a directory and try to create it.
//                        do {
//                            try fileManager.createDirectory(atPath: fullHostPath, withIntermediateDirectories: true, attributes: nil)
//                            print("Info: Created missing host directory for volume: \(fullHostPath)")
//                            runCommandArgs.append("-v")
//                            runCommandArgs.append("\(source):\(destination)") // Use original source for command argument
//                        } catch {
//                            print("Error: Could not create host directory '\(fullHostPath)' for volume '\(resolvedVolume)': \(error.localizedDescription). Skipping this volume.")
//                        }
//                    }
//                } else {
//                    let volumeUrl = URL.homeDirectory.appending(path: ".containers/Volumes/\(projectName)/\(source)")
//                    let volumePath = volumeUrl.path(percentEncoded: false)
//                    
//                    print("Warning: Volume source '\(source)' appears to be a named volume reference. The 'container' tool does not support named volume references in 'container run -v' command. Linking to \(volumePath) instead.")
//                    try fileManager.createDirectory(atPath: volumePath, withIntermediateDirectories: true)
//                    
//                    // Host path exists and is a directory, add the volume
//                    runCommandArgs.append("-v")
//                    // Reconstruct the volume string without mode, ensuring it's source:destination
//                    runCommandArgs.append("\(source):\(destination)") // Use original source for command argument
//                }
//            }
//        }
//
//        // Combine environment variables from .env files and service environment
//        var combinedEnv: [String: String] = envVarsFromFile
//        
//        if let envFiles = service.env_file {
//            for envFile in envFiles {
//                let additionalEnvVars = loadEnvFile(path: "\(currentDirectory)/\(envFile)")
//                combinedEnv.merge(additionalEnvVars) { (current, _) in current }
//            }
//        }
//
//        if let serviceEnv = service.environment {
//            combinedEnv.merge(serviceEnv) { (_, new) in new } // Service env overrides .env files
//        }
//
//        // MARK: Spinning Spot
//        // Add environment variables to run command
//        print(combinedEnv)
//        for (key, value) in combinedEnv {
//            let resolvedValue = resolveVariable(value, with: combinedEnv)
//            print("Resolved value: \(key) | \(resolvedValue)")
//            runCommandArgs.append("-e")
//            runCommandArgs.append("\(key)=\(resolvedValue)")
//        }
//
//        // REMOVED: Port mappings (-p) are not supported by `container run`
//        // if let ports = service.ports {
//        //     for port in ports {
//        //         let resolvedPort = resolveVariable(port, with: envVarsFromFile)
//        //         runCommandArgs.append("-p")
//        //         runCommandArgs.append(resolvedPort)
//        //     }
//        // }
//
//        // Connect to specified networks
////        if let serviceNetworks = service.networks {
////            for network in serviceNetworks {
////                let resolvedNetwork = resolveVariable(network, with: envVarsFromFile)
////                // Use the explicit network name from top-level definition if available, otherwise resolved name
////                let networkToConnect = dockerCompose.networks?[network]?.name ?? resolvedNetwork
////                runCommandArgs.append("--network")
////                runCommandArgs.append(networkToConnect)
////            }
////            print("Info: Service '\(serviceName)' is configured to connect to networks: \(serviceNetworks.joined(separator: ", ")) ascertained from networks attribute in docker-compose.yml.")
////            print("Note: This tool assumes custom networks are defined at the top-level 'networks' key or are pre-existing. This tool does not create implicit networks for services if not explicitly defined at the top-level.")
////        } else {
////            print("Note: Service '\(serviceName)' is not explicitly connected to any networks. It will likely use the default bridge network.")
////        }
//
//        // Add hostname
////        if let hostname = service.hostname {
////            let resolvedHostname = resolveVariable(hostname, with: envVarsFromFile)
////            runCommandArgs.append("--hostname")
////            runCommandArgs.append(resolvedHostname)
////        }
////
////        // Add working directory
////        if let workingDir = service.working_dir {
////            let resolvedWorkingDir = resolveVariable(workingDir, with: envVarsFromFile)
////            runCommandArgs.append("--workdir")
////            runCommandArgs.append(resolvedWorkingDir)
////        }
//
//        // Add privileged flag
////        if service.privileged == true {
////            runCommandArgs.append("--privileged")
////        }
////
////        // Add read-only flag
////        if service.read_only == true {
////            runCommandArgs.append("--read-only")
////        }
////        
////        // Handle service-level configs (note: still only parsing/logging, not attaching)
////        if let serviceConfigs = service.configs {
////            print("Note: Service '\(serviceName)' defines 'configs'. Docker Compose 'configs' are primarily used for Docker Swarm deployed stacks and are not directly translatable to 'container run' commands.")
////            print("This tool will parse 'configs' definitions but will not create or attach them to containers during 'container run'.")
////            for serviceConfig in serviceConfigs {
////                print("  - Config: '\(serviceConfig.source)' (Target: \(serviceConfig.target ?? "default location"), UID: \(serviceConfig.uid ?? "default"), GID: \(serviceConfig.gid ?? "default"), Mode: \(serviceConfig.mode?.description ?? "default"))")
////            }
////        }
////
////        // Handle service-level secrets (note: still only parsing/logging, not attaching)
////        if let serviceSecrets = service.secrets {
////            print("Note: Service '\(serviceName)' defines 'secrets'. Docker Compose 'secrets' are primarily used for Docker Swarm deployed stacks and are not directly translatable to 'container run' commands.")
////            print("This tool will parse 'secrets' definitions but will not create or attach them to containers during 'container run'.")
////            for serviceSecret in serviceSecrets {
////                print("  - Secret: '\(serviceSecret.source)' (Target: \(serviceSecret.target ?? "default location"), UID: \(serviceSecret.uid ?? "default"), GID: \(serviceSecret.gid ?? "default"), Mode: \(serviceSecret.mode?.description ?? "default"))")
////            }
////        }
////
////        // Add interactive and TTY flags
////        if service.stdin_open == true {
////            runCommandArgs.append("-i") // --interactive
////        }
////        if service.tty == true {
////            runCommandArgs.append("-t") // --tty
////        }
////
////        runCommandArgs.append(imageToRun) // Add the image name as the final argument before command/entrypoint
////
////        // Add entrypoint or command
////        if let entrypointParts = service.entrypoint {
////            runCommandArgs.append("--entrypoint")
////            runCommandArgs.append(contentsOf: entrypointParts)
////        } else if let commandParts = service.command {
////            runCommandArgs.append(contentsOf: commandParts)
////        }
////        
////        print("\nStarting service: \(serviceName)")
////        print("Executing container run: container run \(runCommandArgs.joined(separator: " "))")
////        executeCommand(command: "container", arguments: ["run"] + runCommandArgs, detach: detachFlag)
//        print("Service \(serviceName) command execution initiated.")
//        print("----------------------------------------\n")
//    }
//
//} catch {
//    fputs("Error parsing docker-compose.yml: \(error)\n", stderr)
//    exit(1)
//}
