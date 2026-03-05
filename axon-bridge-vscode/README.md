# Axon Bridge for VS Code

Connect VS Code to [Axon](https://axon.app) AI assistant for AI-powered coding assistance. This extension enables Axon to read, write, and execute code in your VS Code workspace.

## Current Release

**Version 0.2.3** - Built February 18, 2026 at 6:19 AM CET

**Filename:** `axon-bridge-0.2.3.vsix`

**Local VSIX:** `/Users/tom/Dropbox (Personal)/Mac (3)/Documents/XCode_Projects/Axon/axon-bridge-vscode/axon-bridge-0.2.3.vsix`

### Included in this build
- Modernized Axon Setup, Axon Chat, and Bridge Logs UI.
- Interactive remote networking controls in Axon Setup (on/off, status, port save).
- LAN URL listing with copy (individual + copy all).
- Live QR generation for mobile auto-connect while networking is ON.

### Download
- [Download Latest VSIX](https://github.com/theMethodolojeeOrg/Axon/raw/main/axon-bridge-vscode/releases/latest/axon-bridge-latest.vsix)
- [Download This Version](https://github.com/theMethodolojeeOrg/Axon/raw/main/axon-bridge-vscode/releases/2025-12-18/axon-bridge-0.2.3_12182025_at_1130PM.vsix)

---

## Features

- **Modern Axon Sidebar UI**: Updated Axon Setup, Axon Chat, and Bridge Logs with responsive layouts.
- **Interactive Remote Networking Setup**: Start/stop networking directly in **Axon Setup**.
- **LAN Address Visibility**: See all detected LAN WebSocket URLs and copy individual or all addresses.
- **Port Management**: Edit remote server port in Axon Setup and persist globally.
- **Mobile Pairing QR**: Generate live QR code payloads for mobile auto-connect when networking is enabled.
- **File + Terminal Tools**: Axon can read/write files and run terminal commands in your workspace.

## Connection Modes

- **Local Mode (`axonBridge.mode = local`)**
  - VS Code connects to Axon running on the same machine.
  - Uses `axonBridge.host` + `axonBridge.port`.
- **Remote Mode (`axonBridge.mode = remote`)**
  - VS Code hosts the server and Axon (e.g. iPhone) connects over LAN.
  - Uses `axonBridge.serverPort` + `axonBridge.serverBindAddress`.

## Axon Setup: Remote Networking Workflow

1. Open the Axon activity bar view and select **Axon Setup**.
2. Click **Turn Networking On**.
   - This switches to Remote Mode (if needed) and starts the VS Code server.
3. Review the generated LAN URLs.
4. Optionally change port in **Server Port (Global)** and click **Save Port**.
   - Port is saved to **global user settings**.
   - If server is running, it restarts on the new port.
5. Scan the QR code from mobile (visible only while networking is ON).

## QR Payload Contract

The setup QR encodes a plain WebSocket URL payload:

- `ws://<ip>:<port>` (default)
- `wss://<ip>:<port>` when `axonBridge.tlsEnabled = true`
- If a pairing token is configured, payload includes:
  - `?pairingToken=<url-encoded-token>`

Example:

- `ws://192.168.1.42:8082?pairingToken=abc123`

## LAN URL + Primary URL Behavior

- Axon Setup detects all non-internal IPv4 addresses from local interfaces.
- All detected URLs are shown and copyable.
- The **primary URL** is the first URL after deterministic sorting.
- QR generation uses the primary URL.
- If no LAN IPv4 is available, setup falls back to `localhost` (or configured bind address) for display.

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
| `axonBridge.mode` | `local` | Connection mode (`local` or `remote`) |
| `axonBridge.host` | `localhost` | Host where Axon is running (Local Mode) |
| `axonBridge.port` | `8081` | WebSocket port for Axon connection (Local Mode) |
| `axonBridge.serverPort` | `8082` | VS Code server listen port (Remote Mode) |
| `axonBridge.serverBindAddress` | `0.0.0.0` | Bind address for LAN access (Remote Mode) |
| `axonBridge.tlsEnabled` | `false` | Use secure WebSocket (`wss://`) |
| `axonBridge.pairingToken` | `""` | Optional shared pairing token |
| `axonBridge.autoConnect` | `true` | Auto connect/start when VS Code starts |
| `axonBridge.reconnectInterval` | `5000` | Reconnect interval (ms) in Local Mode |

## Commands

- **Axon: Connect to Bridge**
- **Axon: Disconnect from Bridge**
- **Axon: Start Server (Remote Mode)**
- **Axon: Stop Server (Remote Mode)**
- **Axon: Show Server Address**
- **Axon: Switch Connection Mode**
- **Axon: Show Bridge Status**
- **Axon: Show Bridge Logs**
- **Axon: Clear Bridge Logs**

## Security Notes

- Pairing token is optional but recommended for Remote Mode.
- Sensitive files (e.g. `.env`, keys) remain guarded by path policy checks.
- All bridge traffic is inspectable in Bridge Logs.

## Troubleshooting

### Networking won't start in Axon Setup

1. Confirm no process already uses `axonBridge.serverPort`.
2. Try a different port in Axon Setup and save.
3. Check the Axon Bridge output/log views for startup errors.

### Mobile cannot connect

1. Ensure phone and computer are on the same LAN.
2. Confirm the selected URL uses your current LAN IP.
3. If pairing token is set, ensure mobile uses the same token.
4. If TLS is enabled, ensure client trust settings match your cert strategy.

## License

MIT
