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

This describes merged code at `ad82911`. It is a practical guide, not an exhaustive Compose conformance matrix. A file decoding successfully does not mean every field is applied: some fields are ignored or only logged, and some valid Compose forms fail decoding.

**Fully supported** below applies only to the specific behavior listed. **Partially supported** means there are syntax or runtime limits. **Unsupported** means Container-Compose does not implement the behavior. **Unsupported upstream** identifies a limitation of Apple Container or macOS itself.

| Feature | Status | Current behavior and limits |
| --- | --- | --- |
| Command surface | Fully supported (listed commands) | `up`, `down`, `build`, `pull`, and `version` are registered. `up` supports service selection, detached operation and rebuilding. This does not imply Docker Compose CLI flag parity. |
| Other Compose commands | Unsupported | No `run`, `ps`, `logs`, `exec`, `start`, `stop`, `restart`, `config`, or `watch` subcommand. Use Apple Container directly where appropriate. |
| Project files and profiles | Partially supported | Finds `compose.yml`, `compose.yaml`, `docker-compose.yml`, or `docker-compose.yaml`; accepts `-f`/`--file`, `--cwd`, profiles and explicit service selection. Project naming uses top-level `name` or the directory name. No multiple-file merge, `include`, or service `extends`; resource isolation is incomplete. |
| Images and builds | Partially supported | Pulls images; builds string contexts or objects with `context`, `dockerfile`, and dictionary `args`. Relative contexts use the Compose file directory; Dockerfiles use the context directory. Supports platform selection and no-cache builds. No build target, list-form args, or full Compose Build specification. |
| Process configuration | Partially supported | Applies command/entrypoint overrides, user, working directory, privileged and read-only flags, container names and dictionary labels. String command/entrypoint handling has known splitting limits; prefer array form. Other service process and security options are not generally implemented. |
| Environment and interpolation | Partially supported | Loads `.env`, service `env_file`, and service environment values. Interpolation is applied at selected call sites, with limited precedence and expression handling; it is not a whole-document Compose interpolation pass. Do not assume every field or Compose environment syntax works. |
| Dependencies and health checks | Partially supported | Orders dependencies and handles started, healthy and successful-completion conditions. Health checks are startup checks, not continuous runtime monitoring; timeout and start-period semantics are incomplete. Independent services launch sequentially. |
| Ports, networks and DNS | Partially supported | Publishes short-form ports and attaches named networks. Creates basic networks or uses external ones; driver/options, internal, attachable, IPv6 and network labels are not applied. DNS uses a registered project domain, otherwise best-effort hosts-file patching. Aliases depend on upstream CLI support. `extra_hosts` replaces the generated hosts file. |
| Storage | Partially supported | Supports short-form service mounts, named-volume creation and external volumes. Relative bind paths currently resolve against the process working directory. Do not assume long-form mount or Docker volume-driver parity. |
| CPU and memory | Partially supported | Maps `deploy.resources.limits.cpus` and memory to runtime flags; `mem_limit` takes precedence for memory and values below 200 MiB are clamped. This is not full resource control: reservations, device reservations, scaling and deployment strategies are not implemented. Fractional CPU handling has pending work. |
| Configs and secrets | Unsupported | Definitions can decode and be logged, but are not created or attached to containers. This is an implementation gap here, not a claim that these features require Swarm. |
| Restart and deployment policy | Unsupported | Restart policies are not applied. Each selected service runs as one container; no replica management, rolling updates or placement scheduling. |
| Container networking on macOS 15 | Unsupported upstream | Apple documents no container-to-container virtual networking and no custom networks on macOS 15. macOS 26 or later is needed for these upstream capabilities. |

The [Compose specification](https://compose-spec.github.io/compose-spec/spec.html) defines syntax and behavior; support is platform dependent. Apple's [command reference](https://github.com/apple/container/blob/main/docs/command-reference.md) describes upstream CLI capabilities, which do not automatically become Compose support here. Its [technical overview](https://github.com/apple/container/blob/main/docs/technical-overview.md#macos-15-limitations) documents the macOS 15 networking restrictions. Upstream main-branch documentation may describe capabilities newer than your installed release.

Pending work is **not available in merged code**: examples include [relative bind paths (#164)](https://github.com/Mcrich23/Container-Compose/pull/164), [build targets (#156)](https://github.com/Mcrich23/Container-Compose/pull/156), [health-check timing (#151)](https://github.com/Mcrich23/Container-Compose/pull/151), and [interpolation (#153)](https://github.com/Mcrich23/Container-Compose/pull/153). Open issue or PR titles can describe older behavior; use the limits above when assessing current support.

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
