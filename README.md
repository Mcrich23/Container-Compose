# Container-Compose

[![Apple Container version](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2FMcrich23%2FContainer-Compose%2Fmain%2FPackage.resolved&search=%22identity%22%5Cs%2A%3A%5Cs%2A%22container%22%5B%5E%7D%5D%2A%22version%22%5Cs%2A%3A%5Cs%2A%22%28%5B%5E%22%5D%2B%29%22&replace=%241&label=Apple+Container&color=blue&logo=apple)](https://github.com/Mcrich23/Container-Compose/blob/main/Package.resolved)
[![Latest release](https://img.shields.io/github/v/release/Mcrich23/Container-Compose?label=release)](https://github.com/Mcrich23/Container-Compose/releases/latest)
[![Static tests](https://img.shields.io/github/actions/workflow/status/Mcrich23/Container-Compose/tests.yml?branch=main&label=static%20tests)](https://github.com/Mcrich23/Container-Compose/actions/workflows/tests.yml)
[![Apache 2.0 license](https://img.shields.io/github/license/Mcrich23/Container-Compose)](https://github.com/Mcrich23/Container-Compose/blob/main/LICENSE)

Container-Compose brings (limited) Docker Compose support to [Apple Container](https://github.com/apple/container), allowing you to define and orchestrate multi-container applications on Apple platforms using familiar Compose files. This project is not a Docker or Docker Compose wrapper but a tool to bridge Compose workflows with Apple's container management ecosystem.

> [!Note]
> Use macOS 26.0 or later for custom networks and container-to-container networking.

## Features

- **Compose file support:** Parse and interpret `docker-compose.yml` files to configure Apple Containers.
- **Apple Container orchestration:** Launch and manage multiple containerized services using Apple’s native container runtime.
- **Environment configuration:** `.env` supplies interpolation values. Service `env_file` entries supply container variables, with later files taking precedence; explicit `environment` values override them.
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
| `down` | Partial | Attempts to stop selected project containers using `stop_grace_period`. | Does not remove containers, networks or named volumes. Uses the shared profile and dependency selection: inactive-profile services are included when explicitly named or required by a selected service, but otherwise skipped. Stop errors are printed and do not fail the command; YAML `stop_signal` is not applied. |
| `build` | Partial | Build from a context path or a mapping with `context`, `dockerfile`, dictionary `args` and `target`. The context defaults to `.`. Both `build` and `up` can select a Dockerfile stage with `target`. | List-form arguments are unsupported. |
| `pull` | Partial | By default, pulls images for enabled services and their dependencies. With explicit service names, pulls only those services unless `--include-deps` is set. Honors an explicit service `platform` and skips build-only services. | No pull-policy selection or option to continue after a pull failure. |
| `ps` | Partial | Lists running project containers with name, image, status and published ports. `-a`/`--all` includes stopped containers. Uses project/service labels, falling back to names for containers without project labels. | No JSON output, quiet mode or status-filter option. Service selection uses the shared dependency resolver, so selecting a service also includes its dependencies. |
| `images` | Partial | Lists service, repository, tag, image ID and size. Uses `<service>:latest` for builds without an explicit image name. Looks up ID and size from local images. | Lists configured service images rather than inspecting the images attached to existing containers. Unavailable local details stay blank. Local matching does not check platform and can match another registry by a short image name. Digest references are split as repository/tag. No JSON or quiet output. Service selection also includes dependencies. |
| `logs` | Partial | Streams logs for enabled or named services concurrently, each line prefixed with a colored service name. Supports `--follow` (also `-f` after `logs`), `--tail`, `--no-color` and `--no-log-prefix`. Named services show only their own logs. Uses project/service labels, falling back to names for containers without project labels. | No `--since`, `--until` or `--timestamps`. `-f` before the subcommand still means `--file`. Services without a container are skipped with a warning. |
| `version` | Supported | Prints the Container-Compose version. | - |
| `run`, `exec`, `start`, `stop`, `restart`, `config`, `watch` | Unsupported | - | These subcommands are not implemented. Use Apple Container directly where appropriate. |

Compose files can be selected with `-f`/`--file`, the working directory with `--cwd`, and the project name with `-p`/`--project-name`. Automatic discovery recognizes `compose.yml`, `compose.yaml`, `docker-compose.yml`, and `docker-compose.yaml`.

`up` and `down` leave containers labeled as belonging to another project alone. Unlabeled containers are matched by name.

Unsupported commands are not aliases for Apple Container commands. For example, use the Apple Container CLI directly to execute a process in an existing container.

### Compose YAML

Decoding a field does not guarantee it is applied at runtime. The table describes implemented behavior and its limits.

| Feature | Support | What works | What is missing or limited |
| --- | --- | --- | --- |
| Project name and profiles | Partial | Uses `--project-name`, `COMPOSE_PROJECT_NAME`, top-level `name`, then the Compose file’s directory name, in that order. Supports profiles and explicit service selection. | Resource isolation is incomplete. |
| Multiple files, `include`, `extends` | Unsupported | - | No file merging, includes or service inheritance. |
| `image` and `platform` | Partial | Run services from an image and select their OS and architecture with `platform`. Missing images are pulled automatically. | Local-image matching does not check platform. Pull policies are unsupported. |
| `build` | Partial | Accepts a context string or a mapping with `context`, `dockerfile`, dictionary `args`, and `target`. Omitted or null context defaults to `.`. Build arguments receive variable substitution. Both `build` and `up` honor `target`. | List-form arguments are unsupported. |
| Build paths | Partial | Build contexts are relative to the Compose file. Dockerfile paths are relative to the context and default to `Dockerfile`. | Paths beginning with `~` are not expanded. |
| `command` and `entrypoint` | Partial | Accepts strings or arrays; arrays separate the executable and arguments. | String form is passed as one argument. Empty entrypoint arrays emit no override, so they do not clear the image entrypoint. Empty command arrays emit no arguments and have no distinct clearing behavior. |
| Process identity and paths | Supported | Set the container user, working directory and name with `user`, `working_dir` and `container_name`. | - |
| Privileges | Partial | Applies `privileged` and `read_only`. | Other security options are not generally implemented. |
| Labels | Partial | Add container labels using a mapping or a list of `key=value` entries. | Reserved Compose project and service labels are overwritten rather than rejected. |
| Environment precedence | Supported | Values in `environment` override `env_file` values, even when empty. Later `env_file` files override earlier ones. `.env` supplies values for `${VARIABLE}` expressions without adding them to the container. | - |
| Environment syntax and loading | Partial | Loads `env_file` and mapping or list `environment` values. | Missing files are ignored. Env-file quoting and interpolation, and null environment inheritance, remain incomplete. |
| Variable interpolation | Partial | Use `$VARIABLE` or `${VARIABLE}` in Compose YAML values, with defaults, required values and nested expressions. Use `$$` for a literal dollar sign. | Top-level `name` is expanded twice, which can expand escaped or substituted variable references again. |
| `depends_on` | Partial | Handles started, healthy and successful-completion conditions. | `required: false` and `restart: true` are decoded but ignored; unavailable optional dependencies can still block startup. Independent services launch sequentially. |
| `healthcheck` | Partial | Runs startup probes with retries, interval and an initial `start_period` delay. Supports `disable: true` and `test: [NONE]`. | Missing or empty tests can count as healthy without probing. No image-inherited probes, probe timeouts or continuous monitoring. |
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

## Support

If you encounter issues or have questions, please open an [Issue](https://github.com/Mcrich23/Container-Compose/issues).

---

Happy Coding! 🚀
