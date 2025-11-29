# K8s Port Forward Manager

An interactive TUI (Text User Interface) tool for managing Kubernetes port forwarding with ease.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-Bash%203.2%2B-green.svg)](https://www.gnu.org/software/bash/)

## Features

- 🚀 **Interactive UI** - Beautiful terminal UI powered by [gum](https://github.com/charmbracelet/gum)
- 🔄 **Auto-reconnect** - Automatically reconnects when port-forward connections drop
- 📝 **Service Management** - Add, edit, and delete services with ease
- 🎯 **Multi-selection** - Start multiple port-forwards simultaneously
- 📊 **Status Monitoring** - Real-time status of running port-forwards
- 📋 **Log Viewing** - View logs for each service
- ⚡ **CLI & UI Modes** - Works with or without gum installed
- 🌐 **Multi-language Support** - English and Korean (한국어) UI

## Demo

```
╔══════════════════════════════════════════╗
║   K8s Port Forward Manager              ║
╚══════════════════════════════════════════╝

● Running: 3 services

🚀 Start Services
⏹️  Stop All
📊 Check Status
📝 Service List
⚙️  Manage Services
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
# Start all services
port-machine start

# Start specific services
port-machine start service1 service2

# Stop all services
port-machine stop

# Check status
port-machine status
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
├── lang-messages.sh           # Multi-language message definitions
└── README.md                  # This file
```

## Configuration Files

- **Service List**: `~/.k8s-port-forward-services.list`
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

## Acknowledgments

- [gum](https://github.com/charmbracelet/gum) - For the beautiful TUI components
- Kubernetes community - For the amazing `kubectl` tool
