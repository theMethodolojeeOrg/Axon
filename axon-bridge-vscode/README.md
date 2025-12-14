# Axon Bridge for VS Code

Connect VS Code to [Axon](https://axon.app) AI assistant for AI-powered coding assistance. This extension enables Axon to read, write, and execute code in your VS Code workspace.

## Features

- **File Operations**: Axon can read and write files in your workspace
- **Terminal Execution**: Run terminal commands with captured output
- **Workspace Awareness**: Axon knows your project structure and open files
- **Secure by Design**: All operations happen locally, with approval for destructive actions

## How It Works

1. Start the Bridge Server in Axon (tap the hotspot icon)
2. This extension automatically connects when VS Code starts
3. Axon can now use tools like `vscode_read_file`, `vscode_write_file`, and `vscode_run_terminal`

## Installation

### From VSIX (Local)

1. Build the extension:
   ```bash
   cd axon-bridge-vscode
   npm install
   npm run compile
   npm run package
   ```

2. Install the `.vsix` file:
   - Open VS Code
   - Press `Cmd+Shift+P` → "Extensions: Install from VSIX..."
   - Select the generated `.vsix` file

### Development

1. Open this folder in VS Code
2. Run `npm install`
3. Press `F5` to launch the Extension Development Host

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `axonBridge.host` | `localhost` | Host where Axon is running |
| `axonBridge.port` | `8081` | WebSocket port for bridge connection |
| `axonBridge.autoConnect` | `true` | Automatically connect when VS Code starts |
| `axonBridge.reconnectInterval` | `5000` | Reconnection interval in milliseconds |

## Commands

- **Axon: Connect to Bridge** - Manually connect to Axon
- **Axon: Disconnect from Bridge** - Disconnect from Axon
- **Axon: Show Bridge Status** - Show current connection status

## Security

- The extension only accepts connections from localhost
- File writes and terminal commands require approval in Axon
- Sensitive files (`.env`, credentials, keys) are blocked by default
- All operations are logged in Axon for audit

## Requirements

- VS Code 1.85.0 or later
- Axon 1.0.0 or later running on the same machine
- Bridge Server started in Axon (hotspot icon)

## Troubleshooting

### Extension doesn't connect

1. Make sure Axon is running
2. Click the hotspot icon in Axon to start the Bridge Server
3. Check that the status shows "Waiting for connection..."
4. Try the "Axon: Connect to Bridge" command in VS Code

### Connection drops frequently

1. Check your `reconnectInterval` setting
2. Ensure Axon stays in the foreground
3. Check Console.app for any network errors

## License

MIT
