# Rails DevContainer

A fully-featured development container configuration for Ruby on Rails projects with integrated tools and services.

## Features

- Pre-configured Ruby on Rails development environment
- Docker Compose setup with Selenium for system testing
- GitHub CLI, Node.js, Python, and AWS CLI pre-installed
- Automatic Ruby version synchronization
- MCP (Model Context Protocol) server integration
- Volume mounts for SSH, AWS, GitHub, and Claude configurations

## Requirements

- Docker Desktop or Docker Engine
- Visual Studio Code with Dev Containers extension
- Git

## Quick Start

1. In your Rails project directory, add this repository as a git subtree:
   ```bash
   git subtree add --prefix=.devcontainer --squash git@github.com:douhashi/devcontainer-rails.git main
   ```

### Visual Studio Code

2. Open your Rails project in VS Code:
   ```bash
   code .
   ```

3. When prompted, click "Reopen in Container" or run the command "Dev Containers: Reopen in Container"

4. Wait for the container to build and post-create scripts to complete

### DevContainer CLI

2. Rebuild and start the development container:
   ```bash
   .devcontainer/bin/rebuild
   .devcontainer/bin/up
   ```

3. The container will build and start with all configured services

## Updating DevContainer

To update the DevContainer configuration with the latest changes from the upstream repository:

```bash
git subtree pull --prefix=.devcontainer --squash git@github.com:douhashi/devcontainer-rails.git main
```

## Configuration

### Ruby Version

The Ruby version is automatically synchronized from `.tool-versions` file. To change it:
1. Update `.tool-versions` in your Rails project
2. Run `sync-ruby-version.sh` to update the DevContainer configuration
3. Rebuild the container

### Services

- **App**: Main Rails application container (ports 5100, 3036)
- **Selenium**: Chrome browser for system tests (port 4444)

### Environment Variables

- `KAMAL_REGISTRY_USERNAME`: Docker registry username for Kamal deployments
- `KAMAL_REGISTRY_PASSWORD`: Docker registry password for Kamal deployments
- `VITE_RUBY_HOST`: Vite development server host (default: 0.0.0.0)
- `SELENIUM_URL`: Selenium server URL for system tests

## Scripts

- `post-create.sh`: Runs after container creation (installs packages, tools, Rails setup)
- `post-attach.sh`: Runs each time you attach to the container
- `sync-ruby-version.sh`: Updates DevContainer Ruby version from .tool-versions

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
