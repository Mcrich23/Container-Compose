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

## Compose support status

- **Fully supported:** The listed behavior works end to end.
- **Partially supported:** Some syntax or behavior is missing.
- **Unsupported:** Not implemented in Container-Compose.
- **Unsupported upstream:** Blocked by Apple Container or macOS.

### Commands

The commands below are available. Their options do not cover every Docker Compose CLI flag.

| Command | Support | Behavior |
| --- | --- | --- |
| `up` | Partial | Starts all enabled services, or named services and their dependencies, in dependency order. Replaces existing containers for the selected services. `-d`/`--detach` returns after startup; foreground mode streams output and stops containers on SIGINT/SIGTERM. `-b`/`--build` requests rebuilding and `--no-cache` disables build caching. YAML limits are listed below. |
| `down` | Partial | Stops selected project containers, honoring service stop settings. Containers, networks and named volumes are not removed. Inactive profiles must be enabled again, or their services named explicitly, to stop them. |
| `build` | Partial | Builds services with a `build` definition; optional service names narrow the selection. Supports `--no-cache`, service `platform`, dictionary build arguments and custom Dockerfiles. Uses `image` as the tag, falling back to `<service>:latest`. Does not start containers. See build syntax below. |
| `pull` | Full | Pulls images for enabled services or explicitly named services. `--include-deps` also pulls dependency images. Uses service platform selection; does not build images or start containers. |
| `version` | Full | Prints the Container-Compose version; this is the tool version, not a Docker Compose compatibility version. |
| `run`, `ps`, `logs`, `exec`, `start`, `stop`, `restart`, `config`, `watch` | Unsupported | Use Apple Container directly where appropriate. |

Compose files can be selected with `-f`/`--file` and the working directory with `--cwd`. Automatic discovery recognizes `compose.yml`, `compose.yaml`, `docker-compose.yml`, and `docker-compose.yaml`.

Unsupported commands are not aliases for Apple Container commands. For example, use the Apple Container CLI directly to inspect logs or execute a process in an existing container.

### Compose YAML

Decoding a field does not guarantee it is applied at runtime. The table describes implemented behavior and its limits.

| Feature | Support | Behavior and limits |
| --- | --- | --- |
| Project name and profiles | Partial | Uses top-level `name` or the directory name. Supports profiles and explicit service selection; resource isolation is incomplete. |
| Multiple files, `include`, `extends` | Unsupported | No file merging, includes or service inheritance. |
| `image` and `platform` | Partial | Image-only services pull their image before starting; service `platform` is passed to the runtime. A service needs an image or build definition. Image pull policy configuration is not implemented. |
| `build` | Partial | Accepts a context string or a mapping with `context`, `dockerfile`, and dictionary `args`. Build arguments receive variable substitution. No build targets or list-form arguments. |
| Build paths | Full | Relative contexts resolve from the Compose file directory; Dockerfile paths resolve from the build context. Omitting `dockerfile` selects `Dockerfile` in that context. |
| `command` and `entrypoint` | Partial | Applies overrides. String splitting has known limits; prefer array form. |
| Process identity and paths | Partial | Applies `user`, `working_dir`, and `container_name`. Otherwise names derive from the project and service, using dotted names when project DNS is registered. |
| Privileges and labels | Partial | Applies `privileged`, `read_only`, and dictionary-form labels. Other security options and list-form labels are not generally implemented. |
| Environment | Partial | Loads `.env`, service `env_file`, and environment values. Some Compose syntax and precedence rules are missing. |
| Variable interpolation | Partial | Expands values at selected call sites, with limited expression handling. Does not interpolate the whole document. |
| `depends_on` | Partial | Handles started, healthy and successful-completion conditions. Independent services launch sequentially. |
| `healthcheck` | Partial | Checks health during startup only. Honors retries and interval, and waits for `start_period` before probing. Per-probe timeout enforcement and continuous health monitoring are missing. |
| Ports | Partial | Publishes short-form port mappings. |
| Networks | Partial | Creates basic named networks or uses external ones. Driver/options, internal, attachable, IPv6 and network labels are not applied. |
| DNS and hosts | Partial | Uses a registered project domain or best-effort hosts-file patching. Aliases depend on upstream CLI support; `extra_hosts` replaces the generated hosts file. |
| Volumes and bind mounts | Partial | Supports short-form mounts, named-volume creation and external volumes. Relative bind paths resolve from the process working directory. Long-form mounts and Docker volume drivers are not fully supported. |
| CPU and memory | Partial | Applies `deploy.resources.limits.cpus` and memory. `mem_limit` takes precedence; memory below 200 MiB is clamped. Fractional CPU handling has known limits. |
| Resource reservations and devices | Unsupported | Does not apply reservations or device reservations. |
| Configs and secrets | Unsupported | Definitions decode and are logged, but resources are not created or attached. |
| Restart and deployment policies | Unsupported | No restart policies, replica management, rolling updates or placement scheduling. Each selected service runs as one container. |

> **Note:** Custom networks and container-to-container networking require macOS 26.0 or later.

See the [Compose specification](https://compose-spec.github.io/compose-spec/spec.html) for YAML syntax and behavior, and Apple's [command reference](https://github.com/apple/container/blob/main/docs/command-reference.md) and [macOS 15 limitations](https://github.com/apple/container/blob/main/docs/technical-overview.md#macos-15-limitations) for upstream capabilities. Features available in Apple Container still need support here.


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
