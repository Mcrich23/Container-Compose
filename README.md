# Container-Compose

Container-Compose brings (limited) Docker Compose support to [Apple Container](https://github.com/apple/container), allowing you to define and orchestrate multi-container applications on Apple platforms using familiar Compose files. This project is not a Docker or Docker Compose wrapper but a tool to bridge Compose workflows with Apple's container management ecosystem.

> **Note:** Container-Compose does not automatically configure DNS for macOS 15 (Sequoia). Use macOS 26 (Tahoe) for an optimal experience.

## Features

- **Compose file support:** Parse and interpret `docker-compose.yml` files to configure Apple Containers.
- **Apple Container orchestration:** Launch and manage multiple containerized services using Apple’s native container runtime.
- **Environment configuration:** Support for environment variable files (`.env`) to customize deployments.
- **Service dependencies:** Specify service dependencies and startup order.
- **Volume and network mapping:** Map data and networking as specified in Compose files to Apple Container equivalents.
- **Extensible:** Designed for future extension and customization.

## Getting Started

### Prerequisites

- A Mac running macOS with Apple Container support (macOS Sonoma or later recommended)
- Git
- [Xcode command line tools](https://developer.apple.com/xcode/resources/) (for building, if building from source)

### Installation

You can install Container-Compose via **Homebrew** (recommended):

```sh
brew update
brew install container-compose
````

Or, build it from source:

1. **Clone the repository:**

   ```sh
   git clone https://github.com/Mcrich23/Container-Compose.git
   cd Container-Compose
   ```

2. **Build the executable:**

   > *Note: Ensure you have Swift installed (or the required toolchain).*

   ```sh
   make build
   ```

3. **(Optional)**: Install globally

   ```sh
   make install
   ```

### Usage

After installation, simply run:

```sh
container-compose up
```

You may need to provide a path to your `docker-compose.yml` and `.env` file as arguments.

## Docker Compose Compatibility

Container-Compose implements a subset of the Docker Compose specification tailored for Apple Container. This section outlines which features are supported, partially supported, or not yet implemented.

### Top-Level Keys

| Feature | Status | Notes |
|---------|--------|-------|
| `version` | ✅ Parsed | Version field is parsed but not enforced |
| `name` | ✅ Supported | Project name used for container naming |
| `services` | ✅ Supported | Core service definitions |
| `networks` | ✅ Supported | Custom network creation and configuration |
| `volumes` | ✅ Supported | Named volumes created as symlinks |
| `configs` | ⚠️ Parsed Only | Parsed but not applied (Swarm feature) |
| `secrets` | ⚠️ Parsed Only | Parsed but not applied (Swarm feature) |

### Service Configuration

#### Core Service Options

| Feature | Status | Notes |
|---------|--------|-------|
| `image` | ✅ Supported | Pull and run from image |
| `build` | ✅ Supported | Build from Dockerfile with context, args, and custom dockerfile |
| `container_name` | ✅ Supported | Custom container naming |
| `command` | ✅ Supported | Override default command |
| `entrypoint` | ✅ Supported | Override default entrypoint |
| `working_dir` | ✅ Supported | Set working directory |
| `user` | ✅ Supported | Run as specific user/UID |
| `hostname` | ✅ Supported | Set container hostname |
| `platform` | ✅ Supported | Specify platform (e.g., `linux/amd64`) |

#### Environment & Variables

| Feature | Status | Notes |
|---------|--------|-------|
| `environment` | ✅ Supported | Environment variables with `${VAR:-default}` substitution |
| `env_file` | ✅ Supported | Load variables from `.env` files |

#### Networking

| Feature | Status | Notes |
|---------|--------|-------|
| `ports` | ✅ Supported | Port mapping (host:container) |
| `networks` | ✅ Supported | Connect to custom networks |
| `expose` | ❌ Not Supported | |
| `dns` | ❌ Not Supported | |
| `dns_search` | ❌ Not Supported | |
| `extra_hosts` | ❌ Not Supported | |
| `mac_address` | ❌ Not Supported | |
| `network_mode` | ❌ Not Supported | |

#### Storage & Volumes

| Feature | Status | Notes |
|---------|--------|-------|
| `volumes` | ✅ Supported | Bind mounts and named volumes |
| `tmpfs` | ❌ Not Supported | |
| `volumes_from` | ❌ Not Supported | |

#### Dependencies & Lifecycle

| Feature | Status | Notes |
|---------|--------|-------|
| `depends_on` | ✅ Supported | Simple array format for startup ordering |
| `restart` | ⚠️ Parsed Only | Parsed but not enforced by Apple Container |
| `healthcheck` | ⚠️ Parsed Only | Parsed but health status not monitored |

#### Security & Privileges

| Feature | Status | Notes |
|---------|--------|-------|
| `privileged` | ✅ Supported | Run in privileged mode |
| `read_only` | ✅ Supported | Read-only root filesystem |
| `stdin_open` | ✅ Supported | Keep stdin open (-i flag) |
| `tty` | ✅ Supported | Allocate pseudo-TTY (-t flag) |
| `cap_add` | ❌ Not Supported | |
| `cap_drop` | ❌ Not Supported | |
| `security_opt` | ❌ Not Supported | |

#### Resource Limits

| Feature | Status | Notes |
|---------|--------|-------|
| `cpus` | ❌ Not Supported | |
| `mem_limit` | ❌ Not Supported | |
| `cpu_shares` | ❌ Not Supported | |
| `deploy.resources` | ⚠️ Parsed Only | Deploy section parsed but not enforced |

#### Advanced Configuration

| Feature | Status | Notes |
|---------|--------|-------|
| `deploy` | ⚠️ Parsed Only | Swarm/orchestration features not applicable |
| `configs` | ⚠️ Parsed Only | Service-level configs parsed but not applied |
| `secrets` | ⚠️ Parsed Only | Service-level secrets parsed but not applied |
| `labels` | ❌ Not Supported | |
| `logging` | ❌ Not Supported | |
| `ulimits` | ❌ Not Supported | |
| `sysctls` | ❌ Not Supported | |

### Build Configuration

| Feature | Status | Notes |
|---------|--------|-------|
| `context` | ✅ Supported | Build context path (relative, absolute, or `~`) |
| `dockerfile` | ✅ Supported | Custom Dockerfile path (relative to context) |
| `args` | ✅ Supported | Build-time variables with environment substitution |
| `target` | ❌ Not Supported | Multi-stage build targets |
| `cache_from` | ❌ Not Supported | |
| `labels` | ❌ Not Supported | |
| `network` | ❌ Not Supported | |
| `shm_size` | ❌ Not Supported | |

### Known Limitations

- **No automatic DNS**: macOS Sonoma and Ventura do not have automatic DNS configuration. Use macOS Tahoe for better experience.
- **No Swarm features**: Deploy configurations, replicas, and placement constraints are not supported.
- **No restart policies**: The `restart` field is parsed but not enforced by Apple Container.
- **Limited healthcheck support**: Healthchecks are parsed but not actively monitored.
- **No resource limits**: CPU and memory limits are not enforced.
- **Configs and Secrets**: These Swarm-specific features are parsed but not applied to containers.

## Contributing

Contributions are welcome! Please open issues or submit pull requests to help improve this project.

1. Fork the repository.
2. Create your feature branch (`git checkout -b feat/YourFeature`).
3. Commit your changes (`git commit -am 'Add new feature'`).
4. Add tests to you changes.
5. Push to the branch (`git push origin feature/YourFeature`).
6. Open a pull request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Support

If you encounter issues or have questions, please open an [Issue](https://github.com/Mcrich23/Container-Compose/issues).

---

Happy Coding! 🚀
