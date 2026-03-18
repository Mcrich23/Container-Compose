# Container-Compose

**Container-Compose is a (mostly) drop-in replacement for `docker-compose` that orchestrates [Apple Containers](https://opensource.apple.com/projects/container/) using the [`container`](https://github.com/apple/container) command.** It brings (currently limited) Docker Compose support, allowing you to define and orchestrate multi-container applications on Apple platforms using familiar compose files. This project aims to bridge Compose workflows with Apple's container management ecosystem. _It is not a Docker or Docker Compose wrapper._

> **Note:** Container-Compose does not automatically configure DNS for macOS 15 (Sequoia). Use macOS 26 (Tahoe) for an optimal experience.

## Features

- **Compose file support:** Parse and interpret Docker Compose files (`docker-compose.yml`) to configure Apple Containers.
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

By default, `container-compose` looks for compose files in the current directory with any of these names:

- `compose.yml`
- `compose.yaml`
- `docker-compose.yml`
- `docker-compose.yaml`

If your compose file does not use one of these names, you will need to use the `--file` option to specify which compose file to use. If your environment file is not `./.env`, you may also need to use the `--env-file` option to specify its location.

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
