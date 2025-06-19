# Container-Compose

Container-Compose brings (limited) Docker Compose support to [Apple Container](https://github.com/apple/container), allowing you to define and orchestrate multi-container applications on Apple platforms using familiar Compose files. This project is not a Docker or Docker Compose wrapper but a tool to bridge Compose workflows with Apple's container management ecosystem.

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
brew tap Mcrich23/formulae
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
   swift build -c release
   ```

3. **(Optional)**: Install globally

   ```sh
   install .build/release/container-compose /usr/local/bin/
   ```

### Usage

After installation, simply run:

```sh
container-compose
```

You may need to provide a path to your `docker-compose.yml` and `.env` file as arguments.

### Directory Structure

```
Container-Compose/
├── docker-compose.yml
├── .env
├── README.md
└── (source code and other configuration files)
```

* `docker-compose.yml`: Your Compose specification.
* `.env`: Your environment variables.
* `README.md`: Project documentation.

### Customization

* **Add a new service:** Edit `docker-compose.yml` and define your new service under the `services:` section.
* **Override configuration:** Use a `docker-compose.override.yml` for local development customizations.
* **Persistent data:** Define named volumes in `docker-compose.yml` for data that should persist between container restarts.

## Contributing

Contributions are welcome! Please open issues or submit pull requests to help improve this project.

1. Fork the repository.
2. Create your feature branch (`git checkout -b feature/YourFeature`).
3. Commit your changes (`git commit -am 'Add new feature'`).
4. Push to the branch (`git push origin feature/YourFeature`).
5. Open a pull request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Support

If you encounter issues or have questions, please open an [Issue](https://github.com/Mcrich23/Container-Compose/issues).

---

Happy Coding! 🚀

```markdown
[![homebrew](https://img.shields.io/badge/install%20with-homebrew-brightgreen)](https://github.com/Mcrich23/homebrew-formulae)
````

Or if you want to auto-detect arch and provide links for x86\_64 vs arm64 downloads in the future.
