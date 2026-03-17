# K8s Port Forward Manager

An interactive TUI (Text User Interface) tool for managing Kubernetes port forwarding with ease.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-Bash%203.2%2B-green.svg)](https://www.gnu.org/software/bash/)

## Features

- 🚀 **Interactive UI** - Beautiful terminal UI powered by [gum](https://github.com/charmbracelet/gum)
- 🔄 **Auto-reconnect** - Automatically reconnects when port-forward connections drop
- 📝 **Service Management** - Add, edit, and delete services with ease
- 🎯 **Multi-selection** - Start multiple port-forwards simultaneously
- 📊 **Status Monitoring** - Real-time status of running port-forwards with Kubernetes context display
- 📋 **Log Viewing** - View logs for each service
- ⚡ **CLI & UI Modes** - Works with or without gum installed
- 🌐 **Multi-language Support** - English and Korean (한국어) UI
- 📁 **Profile Management** - Create and switch between different service configurations
- 📡 **Auto-Discovery** - Automatically detect services from Spring Boot and Docker Compose files
- 🔧 **Easy Upgrade** - Built-in upgrade command to get latest version
- 📖 **Help Command** - Comprehensive help with `-h` or `--help`

## Demo

```
╔══════════════════════════════════════════╗
║   K8s Port Forward Manager v1.4.0       ║
╚══════════════════════════════════════════╝

Current Context: your-k8s-cluster
Current Profile: default

● Running: 3 services

🚀 Start Services
⏹️  Stop All
📊 Check Status
⚙️  Manage Services
📁 Profile Management
💾 Config Management
📋 View Logs
❌ Exit
```

## Prerequisites

- `kubectl` - Kubernetes command-line tool
- `gum` (optional, for enhanced UI) - Install with `brew install gum`

## Installation

### Quick Install

```bash
git clone https://github.com/gyumani/grpc-forward-util.git
cd grpc-forward-util
./install.sh
```

During installation:
1. **Select your preferred language** (English or Korean)
2. The script will automatically:
   - ✅ Add execute permissions to the script
   - ✅ Detect your shell (zsh/bash)
   - ✅ Register `port-machine` alias in both `.zshrc` and `.bashrc`/`.bash_profile`
   - ✅ Save your language preference
   - ✅ Make the command available system-wide

### Manual Installation

```bash
chmod +x dev-port-forward-ui.sh lang-messages.sh
alias port-machine='/path/to/grpc-forward-util/dev-port-forward-ui.sh'
```

Add the alias to your `.zshrc` or `.bashrc` to make it permanent.

## Usage

### Interactive UI Mode

```bash
port-machine
```

### Command Line Mode

```bash
# Show help
port-machine -h
port-machine --help

# Start all services
port-machine start

# Start specific services
port-machine start service1 service2

# Stop all services
port-machine stop

# Check status
port-machine status

# Upgrade to latest version
port-machine upgrade

# Profile management
port-machine profile list
port-machine profile create my-project
port-machine profile switch my-project
port-machine profile delete my-project
```

## Language Settings

The tool supports **English** and **Korean (한국어)** languages.

### Change Language

To change the language preference:

```bash
# Method 1: Re-run installation
./install.sh

# Method 2: Edit config file directly
echo "en" > ~/.port-machine-lang   # For English
echo "ko" > ~/.port-machine-lang   # For Korean (한국어)
```

The language preference is stored in `~/.port-machine-lang` and will be remembered across sessions.

## Upgrade

To upgrade to the latest version, simply run:

```bash
port-machine upgrade
```

Or alternatively:

```bash
cd grpc-forward-util
./upgrade.sh
```

The upgrade script will:
- ✅ Check for new versions from GitHub
- ✅ Show changelog before upgrading
- ✅ Backup your service list and language settings
- ✅ Pull latest changes
- ✅ Restore backups if upgrade fails

**Note**: Upgrade feature requires Git installation. Make sure you installed via `git clone`.

## Configuration

Services are stored in `~/.k8s-port-forward-services.list` in the following format:

```
service-name|namespace|local-port|remote-port
```

Example:
```
my-api-svc|dev|8080|9090
grpc-server-svc|production|9999|50051
```

### Managing Services

Use the interactive UI to manage services:

1. Launch `port-machine`
2. Select "⚙️ Service Management"
3. Choose from:
   - ➕ Add Service
   - ➖ Delete Service (multi-select)
   - ✏️ Edit Port

### Auto-Discovery from Project Files

**NEW in v1.5.0**: Automatically discover and import services from your project configuration files!

The auto-discovery feature scans your project for service configurations and automatically creates port-forward entries. This eliminates manual service configuration and speeds up setup.

#### Supported File Formats

- **Spring Boot** - `application-*.yaml`, `application-*.yml` (profile-specific configs), `application.properties`
  - **gRPC Client Configuration** (v1.5.2+) - Parses `grpc.client.*` sections to discover client services
- **Docker Compose** - `docker-compose.yaml`, `docker-compose.yml`

#### How to Use Auto-Discovery

1. Navigate to your project directory
2. Launch `port-machine`
3. Select "💾 Config Management"
4. Select "📡 Auto-discover from Project"
5. The tool will:
   - Find your project root (by detecting `.git`, `package.json`, `build.gradle`, `pom.xml`, etc.)
   - Scan for configuration files
   - Extract service names and ports
   - Display discovered services in a table
6. Select services to import (multi-select with Space key)
7. Confirm to add them to your service list

#### What Gets Discovered

**From Spring Boot files:**
- Service name from `spring.application.name`
- Server port from `server.port` or `grpc.server.port`
- **gRPC Client Services** (v1.5.2+): Automatically discovers gRPC client configurations
  - Extracts service names from `grpc.client.*` section
  - Parses local ports from `address` field (e.g., `static://localhost:9998`)
  - Remote port set to 9090 for all services

**From Docker Compose:**
- Service names from service definitions
- Ports from port mappings

**Example 1: Basic Spring Boot Server**

If your `application-dev.yaml` contains:
```yaml
spring:
  application:
    name: user-service
server:
  port: 8080
```

The tool will discover:
- Service: `user-service-svc`
- Namespace: `default`
- Local Port: `8080`
- Remote Port: `9090`

**Example 2: gRPC Client Configuration (NEW in v1.5.2)**

If your `application-local.yaml` contains:
```yaml
grpc:
  server:
    port: 9999
  client:
    pms-supplier:
      address: 'static://localhost:9998'
    infra-common:
      address: 'static://localhost:9997'
    infra-message:
      address: 'static://localhost:9111'
```

The tool will discover:
- Service: `pms-supplier` → Local: `9998`, Remote: `9090`
- Service: `infra-common` → Local: `9997`, Remote: `9090`
- Service: `infra-message` → Local: `9111`, Remote: `9090`
- Service: `user-service-svc` → Local: `9999`, Remote: `9090` (server port)

**Note**:
- Auto-discovery searches profile-specific files (`application-*.yaml`) only
- Duplicate service names are automatically removed (first occurrence kept)
- All remote ports are standardized to 9090

### Profile Management

Profiles allow you to save and switch between different service configurations. This is useful when working with multiple projects or environments.

#### Creating a Profile

Save your current service configuration as a profile:

```bash
# UI Mode
port-machine
# Select "📁 Profile Management" > "➕ Create Profile"

# CLI Mode
port-machine profile create my-project "Development services for my project"
```

#### Switching Profiles

Switch between different profiles:

```bash
# UI Mode
port-machine
# Select "📁 Profile Management" > "🔄 Switch Profile"

# CLI Mode
port-machine profile switch my-project
```

#### Listing Profiles

View all available profiles:

```bash
# UI Mode
port-machine
# Select "📁 Profile Management" > "📋 List Profiles"

# CLI Mode
port-machine profile list
```

#### Deleting Profiles

Remove a profile (note: "default" profile cannot be deleted):

```bash
# UI Mode
port-machine
# Select "📁 Profile Management" > "➖ Delete Profile"

# CLI Mode
port-machine profile delete my-project
```

**Note**: When you switch profiles, the current service list is automatically backed up with a timestamp.

## Features in Detail

### Auto-reconnect

Port-forwards automatically reconnect when the connection drops, ensuring your development workflow isn't interrupted.

### Logs

Logs for each service are stored in `/tmp/k8s-port-forward-logs/`:
- View logs directly from the UI
- Tail the last 50 lines per service
- Helpful for debugging connection issues

### Multi-service Support

Start multiple port-forwards simultaneously:
- Select services using Space key
- Confirm with Enter
- All selected services start in the background

## Compatibility

- ✅ macOS (Bash 3.2+)
- ✅ Linux (Bash 4.0+)
- ✅ Works with both `zsh` and `bash`

## File Structure

```
grpc-forward-util/
├── dev-port-forward-ui.sh    # Main script
├── install.sh                 # Installation script
├── upgrade.sh                 # Upgrade script
├── lang-messages.sh           # Multi-language message definitions
├── VERSION                    # Current version
├── LICENSE                    # MIT License
├── .gitignore                 # Git ignore rules
└── README.md                  # This file
```

## Configuration Files

- **Service List**: `~/.k8s-port-forward-services.list`
- **Profiles**: `~/.port-machine-profiles/` (YAML files for each profile)
- **Current Profile**: `~/.port-machine-current-profile`
- **Language Config**: `~/.port-machine-lang`
- **PID Tracking**: `/tmp/k8s-port-forward.pids`
- **Logs**: `/tmp/k8s-port-forward-logs/`

## Troubleshooting

### Command not found

After installation, run:
```bash
source ~/.zshrc   # for zsh
source ~/.bashrc  # for bash
```

Or open a new terminal window.

### Port already in use

Check for existing port-forwards:
```bash
port-machine status
```

Stop all port-forwards:
```bash
port-machine stop
```

### gum not installed

The tool will fall back to a basic CLI mode if `gum` is not installed. For the best experience:
```bash
brew install gum
```

### Changing Language

If the UI language is not what you expect:
```bash
# Check current language setting
cat ~/.port-machine-lang

# Change to English
echo "en" > ~/.port-machine-lang

# Change to Korean
echo "ko" > ~/.port-machine-lang
```

### Getting Help

For a quick reference of all commands:
```bash
port-machine -h
```

This will display:
- Available commands
- Command descriptions
- Usage examples
- Current version

## Disclaimer

⚠️ **This tool is for development purposes only.**

- Ensure you understand your cluster's security policies before using port-forwarding
- Port-forwarding can expose services that should remain internal
- Use responsibly and only on development/staging environments
- Always follow your organization's security guidelines

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

Created with ❤️ for easier Kubernetes development workflow

## Changelog

### v1.5.2 (2026-03-17)
**Patch Release - gRPC Client Discovery**

#### ✨ New Features
- 🔌 **gRPC Client Configuration Parsing**: Automatically discovers gRPC client services from Spring Boot configs
  - Parses `grpc.client.*` sections in `application-*.yaml` files
  - Extracts service names and ports from address fields (e.g., `static://localhost:9998`)
  - Each gRPC client becomes a separate discoverable service
- 🎯 **Profile-Specific File Discovery**: Now scans only `application-*.yaml` and `application-*.yml` files
  - Excludes base `application.yaml` to reduce noise
  - Focuses on environment-specific configurations (dev, local, prod, etc.)
- 🔄 **Duplicate Service Removal**: Automatically removes duplicate service names during discovery
  - First occurrence is kept when duplicates are found
  - Cleaner service list without manual cleanup

#### 🔧 Changes
- **Standardized Remote Ports**: All discovered services now use port 9090 as remote port
- **Improved YAML Parsing**: State machine approach for nested gRPC client configurations
- **Better Discovery Output**: Progress messages during file scanning

#### 📝 Documentation
- Updated README with gRPC client discovery examples
- Added detailed parsing behavior documentation
- Added notes about profile-specific file patterns
- Updated supported file formats section

---

### v1.5.1 (2026-03-17)
**Patch Release - Version Update**

#### 🔧 Changes
- Minor version increment for tracking purposes

---

### v1.5.0 (2026-03-17)
**Minor Release - Auto-Discovery**

#### ✨ New Features
- 📡 **Auto-Discovery from Project Files**: Automatically detect and import services from configuration files
- 🔍 **Smart Project Root Detection**: Searches up to 10 levels to find project root
- 🌱 **Spring Boot Support**: Parses `application.yaml`, `application.yml`, and `application.properties`
- 🐳 **Docker Compose Support**: Extracts services and ports from `docker-compose.yaml` files
- 🎯 **Multi-Select Import**: Choose which discovered services to import
- 📊 **Discovery Preview**: View all discovered services in a table before importing

#### 🔧 Features
- Automatic extraction of service names from `spring.application.name`
- Port detection from `server.port` and `grpc.server.port` in Spring Boot
- Docker Compose service and port mapping parser
- Project root markers: `.git`, `package.json`, `build.gradle`, `pom.xml`, `Cargo.toml`, `go.mod`
- Duplicate service detection during import
- Multi-language support for all auto-discovery features

#### 📝 Documentation
- Added comprehensive Auto-Discovery guide in README
- Added supported file formats documentation
- Added usage examples with sample configurations

---

### v1.4.0 (2026-03-17)
**Minor Release - Profile Management**

#### ✨ New Features
- 📁 **Profile Management**: Save and switch between different service configurations
- 🎨 **Profile UI**: Dedicated profile management menu in interactive UI
- 🔄 **Profile Switching**: Seamlessly switch between projects with automatic backup
- 📊 **Profile Information**: View profile details including service count and creation date
- 💻 **CLI Support**: Full CLI commands for profile operations (`create`, `switch`, `list`, `delete`)

#### 🔧 Features
- Profile directory structure at `~/.port-machine-profiles/`
- Profile format: YAML with metadata (name, description, created date)
- Automatic backup when switching profiles (timestamped)
- Current profile tracking and display in main UI
- Protected "default" profile cannot be deleted
- Multi-language support for all profile features

#### 📝 Documentation
- Added comprehensive Profile Management guide in README
- Updated configuration files section
- Added CLI command examples for profile operations

---

### v1.3.2 (2025-03-16)
**Patch Release - Bug Fix**

#### 🐛 Bug Fixes
- Fixed menu selection issue where "Config Management" menu incorrectly redirected to "Service Management"
- Improved menu condition matching order to prioritize more specific patterns
- Changed Korean menu matching from "관리" to "서비스" to avoid conflicts

#### 🔧 Changes
- Refactored menu selection logic for better reliability
- Removed duplicate Config Management code block

---

### v1.3.1 (2025-11-29)
**Minor Release - Version Display & Context Monitoring**

#### ✨ New Features
- 📌 **Version Display**: Version number shown in UI header (e.g., "K8s Port Forward Manager v1.3.1")
- 🎯 **Kubernetes Context Display**: Current kubectl context shown on main screen
- 📖 **Help Command**: Added `-h`, `--help`, and `help` commands for usage information

#### 🔧 Changes
- Version information integrated into header title
- Real-time Kubernetes context monitoring
- Improved help documentation with examples

---

### v1.2.1 (2025-11-29)
**Minor Release - Upgrade Command**

#### ✨ New Features
- 🔧 **Upgrade Command**: Added `port-machine upgrade` for easy version updates
- Integrated upgrade functionality into main command

### v1.1.1 (2025-11-29)
**Minor Release - Multi-language Support & UI Improvements**

#### ✨ New Features
- 🌐 **Multi-language Support**: Full English and Korean (한국어) UI
- 🎨 **Improved Service Management**: Consolidated service list into management screen
- 📊 **Enhanced Display**: Show remote port in service management view

#### 🔧 Changes
- Removed redundant "Service List" menu (now integrated into Service Management)
- Service Management now displays 4 columns: Service Name, Namespace, Local Port, Remote Port
- Language preference is saved and persists across sessions
- Improved menu organization (6 main menu items instead of 7)

#### 🐛 Bug Fixes
- Fixed Bash 3.2 compatibility issues with associative arrays
- Fixed menu selection pattern matching for multi-language support
- Improved case-insensitive menu matching

#### 📝 Documentation
- Added comprehensive README with installation guide
- Added LICENSE (MIT)
- Added .gitignore for better repository management
- Added disclaimer and security guidelines

---

### v1.0.0 (Initial Release)
- ✅ Interactive TUI for Kubernetes port-forwarding
- ✅ Auto-reconnect on connection drop
- ✅ Multi-service selection
- ✅ Service CRUD operations
- ✅ Log viewing
- ✅ CLI fallback mode
- ✅ gum-based beautiful UI

## Acknowledgments

- [gum](https://github.com/charmbracelet/gum) - For the beautiful TUI components
- Kubernetes community - For the amazing `kubectl` tool
