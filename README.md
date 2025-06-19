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
- [Xcode command line tools](https://developer.apple.com/xcode/resources/) (for building)

### Installation

1. **Clone the repository:**
   ```sh
   git clone https://github.com/Mcrich23/Container-Compose.git
   cd Container-Compose
   ```

2. **Build the executable:**
   > _Note: Ensure you have the required toolchain (e.g., Swift, Go, etc.) installed for building the executable._
   ```sh
   # Example for Swift:
   swift build -c release
   ```

   Adjust the build command above based on the technology used in this repository.

### Usage

Currently, Container-Compose is only invoked by building and running the executable yourself.

1. **Run the executable:**
   ```sh
   ./container-compose
   ```
   You may need to provide a path to your `docker-compose.yml` and `.env` file as arguments.

2. **Manage your Apple Containers** as defined in your Compose file.

### Directory Structure

```
Container-Compose/
├── docker-compose.yml
├── .env.example
├── README.md
└── (source code and other configuration files)
```

- `docker-compose.yml`: Your Compose specification.
- `.env.example`: Template for environment variables.
- `README.md`: Project documentation.

### Customization

- **Add a new service:** Edit `docker-compose.yml` and define your new service under the `services:` section.
- **Override configuration:** Use a `docker-compose.override.yml` for local development customizations.
- **Persistent data:** Define named volumes in `docker-compose.yml` for data that should persist between container restarts.

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
