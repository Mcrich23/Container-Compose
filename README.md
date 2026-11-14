# Container-Compose

Container-Compose brings (limited) Docker Compose support to [Apple Container](https://github.com/apple/container), allowing you to define and orchestrate multi-container applications on Apple platforms using familiar Compose files. This project is not a Docker or Docker Compose wrapper but a tool to bridge Compose workflows with Apple's container management ecosystem.

> [!Note]
> Use macOS 26.0 or later for custom networks and container-to-container networking.

## Features

- **Compose file support:** Parse and interpret `docker-compose.yml` files to configure Apple Containers.
- **Apple Container orchestration:** Launch and manage multiple containerized services using Apple’s native container runtime.
- **Environment configuration:** Support for environment variable files (`.env`) to customize deployments.
- **Service dependencies:** Specify service dependencies and startup order.
- **Volume and network mapping:** Map data and networking as specified in Compose files to Apple Container equivalents.
- **Extensible:** Designed for future extension and customization.

## Compose support status

- **Supported:** The listed behavior is implemented without the limitations described for partial support.
- **Partially supported:** Some syntax or behavior is missing.
- **Unsupported:** Not implemented in Container-Compose.

### Commands

Command support includes both available behavior and known gaps. A command being present does not mean it behaves like Docker Compose in every case.

| Command | Support | What works | What is missing or limited |
| --- | --- | --- | --- |
| `up` | Partial | Starts enabled or explicitly named services and their dependencies in dependency order. Attempts to stop and remove existing selected containers before starting replacements. Supports detached operation, foreground output, rebuilding with `-b`/`--build`, and `--no-cache`. | Foreground signal handling is installed only after service startup, leaving startup and health-check waits uncovered. Use `down` to stop them. Independent services start sequentially. `--no-cache` only affects a build that runs; use `--build` to rebuild an existing local image. Cleanup errors are printed and startup continues. Other YAML limits are listed below. |
| `down` | Partial | Attempts to stop selected project containers using `stop_grace_period`. | Does not remove containers, networks or named volumes. Uses the shared profile and dependency selection: inactive-profile services are included when explicitly named or required by a selected service, but otherwise skipped. Container lookup uses candidate names rather than checking project labels. Stop errors are printed and do not fail the command; YAML `stop_signal` is not applied. |
| `build` | Partial | Builds selected services and their buildable dependencies. Supports `--no-cache`, service `platform` including variants such as `linux/arm64/v8`, dictionary build arguments, custom Dockerfiles and `build.target`. Tags images with `image` or `<service>:latest`. | No CLI `--build-arg` override or list-form YAML arguments. Other Compose build options, such as inline Dockerfiles and cache import/export, are not implemented. |
| `pull` | Partial | By default, pulls images for enabled services and their dependencies. With explicit service names, pulls only those services unless `--include-deps` is set. Honors an explicit service `platform` and skips build-only services. | No pull-policy selection or option to continue after a pull failure. |
| `ps` | Partial | Lists running project containers with name, image, status and published ports. `-a`/`--all` includes stopped containers. Uses project/service labels, falling back to names for containers without project labels. | No JSON output, quiet mode or status-filter option. Service selection uses the shared dependency resolver, so selecting a service also includes its dependencies. |
| `images` | Partial | Lists service, repository, tag, image ID and size. Uses `<service>:latest` for builds without an explicit image name. Looks up ID and size from local images. | Lists configured service images rather than inspecting the images attached to existing containers. Unavailable local details stay blank. Local matching does not check platform and can match another registry by a short image name. Digest references are split as repository/tag, and variables are displayed literally. No JSON or quiet output. Service selection also includes dependencies. |
| `version` | Supported | Prints the Container-Compose version. | - |
| `run`, `logs`, `exec`, `start`, `stop`, `restart`, `config`, `watch` | Unsupported | - | These subcommands are not implemented. Use Apple Container directly where appropriate. |

Compose files can be selected with `-f`/`--file` and the working directory with `--cwd`. Automatic discovery recognizes `compose.yml`, `compose.yaml`, `docker-compose.yml`, and `docker-compose.yaml`.

Unsupported commands are not aliases for Apple Container commands. For example, use the Apple Container CLI directly to inspect logs or execute a process in an existing container.

### Compose YAML

Decoding a field does not guarantee it is applied at runtime. The table describes implemented behavior and its limits.

| Feature | Support | What works | What is missing or limited |
| --- | --- | --- | --- |
| Project name and profiles | Partial | Uses top-level `name` or the directory name. Supports profiles and explicit service selection. | Resource isolation is incomplete. |
| Multiple files, `include`, `extends` | Unsupported | - | No file merging, includes or service inheritance. |
| `image` and `platform` | Partial | Image-only services pull before starting when no matching local reference is found. Service `platform` is passed to the runtime. | Local-image matching does not check platform. A service needs an image or build definition. Image pull policy configuration is not implemented. |
| `build` | Partial | Accepts a context string or a mapping with `context`, `dockerfile`, dictionary `args`, and `target`. Omitted or null context defaults to `.`. Build arguments receive variable substitution. Both `build` and `up` honor `target`. | List-form arguments are unsupported. |
| Build paths | Partial | Relative contexts resolve from the Compose file directory; Dockerfile paths resolve from the build context. Omitting `dockerfile` selects `Dockerfile` in that context. | Context and Dockerfile paths do not receive variable interpolation or explicit tilde expansion. |
| `command` and `entrypoint` | Partial | Accepts strings or arrays; arrays separate the executable and arguments. | String form is passed as one argument. Empty entrypoint arrays emit no override, so they do not clear the image entrypoint. Empty command arrays emit no arguments and have no distinct clearing behavior. |
| Process identity and paths | Partial | Applies `user`, `working_dir`, and `container_name`. Otherwise names derive from the project and service, using dotted names when project DNS is registered. | `user` and `container_name` do not receive variable interpolation. |
| Privileges | Partial | Applies `privileged` and `read_only`. | Other security options are not generally implemented. |
| Labels | Partial | Accepts mappings or lists. List entries split at the first `=`; bare names and explicit empty values become empty strings, and later duplicate names win. Passes labels to the container. | Generated Compose project/service labels override user values for those two keys. Label values do not receive variable interpolation. |
| Environment | Partial | Loads `.env`, service `env_file`, and mapping or list environment values. Literal service values override file values. | `.env` wins over `env_file`, and earlier env files win over later ones. Values containing `${` follow a separate, limited substitution path. Missing env files are silently ignored; dotenv quoting and full Compose precedence are not implemented. |
| Variable interpolation | Partial | Expands values at selected call sites. | Expression handling is limited. Does not interpolate the whole document. |
| `depends_on` | Partial | Handles started, healthy and successful-completion conditions. | `required: false` and `restart: true` are decoded but ignored; unavailable optional dependencies can still block startup. Independent services launch sequentially. |
| `healthcheck` | Partial | Runs startup probes, honors retries and interval, and waits for `start_period` before probing. `disable: true` or `test: [NONE]` disables checks. | Absent or empty tests can be marked healthy without a probe; image-inherited HEALTHCHECK probes are not executed. Per-probe timeout enforcement and continuous health monitoring are missing. |
| Ports | Partial | Passes short-form mappings to the runtime. | A bare container port publishes the same host port on `0.0.0.0`, rather than requesting an ephemeral host port. Long-form mappings are unsupported. |
| Networks | Partial | Creates basic named networks or uses external ones. | Driver/options, internal, attachable, IPv6 and network labels are not applied. No project-specific implicit default network is created. Legacy external network names are not used when attaching services; use the top-level network `name`. |
| Automatic DNS registration | Unsupported | - | Checks for an existing DNS domain but does not register one. Register it separately with `sudo container system dns create <domain>`. |
| DNS and hosts | Partial | Uses a registered project domain or best-effort hosts-file patching. `extra_hosts` bind-mounts a replacement `/etc/hosts`. | Network aliases are ignored. `hostname` does not set the runtime hostname. The replacement hosts file discards daemon-managed entries. `host-gateway` uses network inspection with a potentially unreachable LAN-gateway fallback. |
| Volumes and bind mounts | Partial | Supports short-form source/destination mounts, named-volume creation and external volumes. Relative bind paths resolve from the Compose file directory, including with `-f`. Volume driver names, options and labels are forwarded. | Long-form and destination-only anonymous mounts are unsupported. Null top-level definitions are skipped during explicit volume creation. The pinned Apple Container implementation creates local ext4 images regardless of driver name; it interprets `size` and `journal` and stores other options without applying Docker driver behavior. |
| CPU and memory | Partial | Passes runtime CPU limits from `deploy.resources.limits.cpus`. Applies memory limits, giving `mem_limit` precedence and clamping memory below 200 MiB. | Build CPU values must parse as integers or fall back to 2. Build memory uses deploy limits or its default, without the runtime clamp or `mem_limit` precedence. |
| Resource reservations and devices | Unsupported | - | Does not apply reservations or device reservations. |
| External resource declarations | Partial | Accepts boolean `external` values and legacy `{name: shared}` on volumes, networks, configs and secrets. Malformed declarations fail decoding instead of silently falling back to local resources. | Config and secret attachments remain unimplemented. |
| Configs and secrets | Unsupported | - | Definitions and attachments decode, and service attachments are logged, but resources are not created or attached. |
| Restart and deployment policies | Unsupported | - | No restart policies, replica management, rolling updates or placement scheduling. Each selected service runs as one container. |

> [!Note]
> Custom networks and container-to-container networking require macOS 26.0 or later.

See the [Compose specification](https://compose-spec.github.io/compose-spec/spec.html) for YAML syntax and behavior, and Apple's [command reference](https://github.com/apple/container/blob/main/docs/command-reference.md) and [macOS 15 limitations](https://github.com/apple/container/blob/main/docs/technical-overview.md#macos-15-limitations) for upstream capabilities. Features available in Apple Container still need support here.


## Getting Started

### Prerequisites

- A Mac with Apple silicon. The package targets macOS 15 or later; macOS 26.0 or later is recommended and required for custom networks and container-to-container networking.
- [Apple Container](https://github.com/apple/container) installed, with its system running for container operations (`container system start`).
- For source builds: Git and a Swift 6.1 or later toolchain, available through [Xcode](https://developer.apple.com/xcode/resources/).

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
