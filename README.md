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

Command support includes both available behavior and known gaps. A command being present does not mean it behaves like Docker Compose in every case.

| Command | Support | What works | What is missing or limited |
| --- | --- | --- | --- |
| `up` | Partial | Starts enabled services, or named services and their dependencies, in dependency order. Replaces existing containers for selected services. Supports detached operation, foreground output, rebuilding with `-b`/`--build`, and `--no-cache`. | SIGTERM does not reliably stop containers: signal handling is installed only after service startup, leaving startup and health-check waits uncovered. Use `down` to stop them. Independent services start sequentially. Builds through `up` ignore `build.target`. Other YAML limits are listed below. |
| `down` | Partial | Stops selected project containers using each service's stop settings. | Does not remove containers, networks or named volumes. Services in inactive profiles are skipped unless their profile is enabled or they are named explicitly. Container lookup uses candidate names rather than checking project labels. |
| `build` | Partial | Builds selected services and their buildable dependencies. Supports `--no-cache`, service `platform`, dictionary build arguments, custom Dockerfiles and `build.target`. Tags images with `image` or `<service>:latest`. | No CLI `--build-arg` override or list-form YAML arguments. Other Compose build options, such as inline Dockerfiles and cache import/export, are not implemented. |
| `pull` | Partial | Pulls images for enabled or explicitly named services. `--include-deps` includes dependency images. Honors an explicit service `platform` and skips build-only services. | Without an explicit platform, pulls can download every architecture in an image index. No pull-policy selection or option to continue after a pull failure. |
| `ps` | Partial | Lists running project containers with name, image, status and published ports. `-a`/`--all` includes stopped containers. Uses project/service labels, falling back to names for containers without project labels. | No JSON output, quiet mode or status-filter option. Service selection uses the shared dependency resolver, so selecting a service also includes its dependencies. |
| `images` | Partial | Lists service, repository, tag, image ID and size. Uses `<service>:latest` for builds without an explicit image name. Looks up ID and size from local images. | Lists configured service images rather than inspecting the images attached to existing containers. Unavailable local details stay blank. No JSON or quiet output. Service selection also includes dependencies. |
| `version` | Full | Prints the Container-Compose version. | Reports this tool's version, not a Docker Compose compatibility version. |
| `run`, `logs`, `exec`, `start`, `stop`, `restart`, `config`, `watch` | Unsupported | — | These subcommands are not implemented. Use Apple Container directly where appropriate. |

Compose files can be selected with `-f`/`--file` and the working directory with `--cwd`. Automatic discovery recognizes `compose.yml`, `compose.yaml`, `docker-compose.yml`, and `docker-compose.yaml`.

Unsupported commands are not aliases for Apple Container commands. For example, use the Apple Container CLI directly to inspect logs or execute a process in an existing container.

### Compose YAML

Decoding a field does not guarantee it is applied at runtime. The table describes implemented behavior and its limits.

| Feature | Support | Behavior and limits |
| --- | --- | --- |
| Project name and profiles | Partial | Uses top-level `name` or the directory name. Supports profiles and explicit service selection; resource isolation is incomplete. |
| Multiple files, `include`, `extends` | Unsupported | No file merging, includes or service inheritance. |
| `image` and `platform` | Partial | Image-only services pull their image before starting; service `platform` is passed to the runtime. A service needs an image or build definition. Image pull policy configuration is not implemented. |
| `build` | Partial | Accepts a context string or a mapping with `context`, `dockerfile`, dictionary `args`, and `target`. Omitted or null context defaults to `.`. Build arguments receive variable substitution; list-form arguments are not supported. The `build` command honors `target`, but builds started by `up` do not yet apply it. |
| Build paths | Full | Relative contexts resolve from the Compose file directory; Dockerfile paths resolve from the build context. Omitting `dockerfile` selects `Dockerfile` in that context. |
| `command` and `entrypoint` | Partial | Applies overrides. String splitting has known limits; prefer array form. |
| Process identity and paths | Partial | Applies `user`, `working_dir`, and `container_name`. Otherwise names derive from the project and service, using dotted names when project DNS is registered. |
| Privileges | Partial | Applies `privileged` and `read_only`. Other security options are not generally implemented. |
| Labels | Full | Accepts mappings or lists. List entries split at the first `=`; bare names and explicit empty values become empty strings, and later duplicate names win. Passes labels to the container alongside Compose project/service labels. |
| Environment | Partial | Loads `.env`, service `env_file`, and environment values. Some Compose syntax and precedence rules are missing. |
| Variable interpolation | Partial | Expands values at selected call sites, with limited expression handling. Does not interpolate the whole document. |
| `depends_on` | Partial | Handles started, healthy and successful-completion conditions. Independent services launch sequentially. |
| `healthcheck` | Partial | Checks health during startup only. Honors retries and interval, and waits for `start_period` before probing. Per-probe timeout enforcement and continuous health monitoring are missing. |
| Ports | Partial | Publishes short-form port mappings. |
| Networks | Partial | Creates basic named networks or uses external ones. Driver/options, internal, attachable, IPv6 and network labels are not applied. |
| DNS and hosts | Partial | Uses a registered project domain or best-effort hosts-file patching. Aliases depend on upstream CLI support; `extra_hosts` replaces the generated hosts file. |
| Volumes and bind mounts | Partial | Supports short-form mounts, named-volume creation and external volumes. Relative bind paths resolve from the Compose file directory, including when the file is selected with `-f`. Long-form mounts and Docker volume drivers are not fully supported. |
| CPU and memory | Partial | Applies `deploy.resources.limits.cpus` and memory. `mem_limit` takes precedence; memory below 200 MiB is clamped. Fractional CPU handling has known limits. |
| Resource reservations and devices | Unsupported | Does not apply reservations or device reservations. |
| External resource declarations | Partial | Accepts boolean `external` values and the legacy `{name: shared}` form on volumes, networks, configs and secrets. Malformed declarations fail decoding instead of silently falling back to local resources. Config and secret attachments remain unimplemented. |
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
