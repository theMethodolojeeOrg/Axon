/**
 * extension.ts
 *
 * Entry point for the Axon Bridge VS Code extension.
 * Supports two connection modes:
 * - Local Mode: VS Code connects to Axon (default)
 * - Remote Mode: VS Code acts as server, Axon connects over LAN
 */

import * as vscode from 'vscode';
import { BridgeConnectionManager } from './BridgeConnectionManager';
import { StatusBar } from './ui/StatusBar';
import { BridgeLogService } from './BridgeLogService';
import { BridgeLogsViewProvider } from './ui/BridgeLogsViewProvider';
import { AxonSetupViewProvider } from './ui/AxonSetupViewProvider';
import { AxonChatViewProvider } from './ui/AxonChatViewProvider';
// TLSConfig imported for future TLS fingerprint display
// import { showCertificateFingerprint } from './TLSConfig';
import { BridgeMode } from './Protocol';

let connectionManager: BridgeConnectionManager;
let statusBar: StatusBar;

export function activate(context: vscode.ExtensionContext) {
    console.log('[AxonBridge] Extension activating...');

    // Use a try-catch block for the entire activation to ensure at least logs/UI work
    // even if connection manager or other parts fail.
    try {
        const activationOutput = vscode.window.createOutputChannel('Axon Bridge (Activation)');
        activationOutput.appendLine(`[AxonBridge] activating (cwd: ${process.cwd()})`);
        activationOutput.appendLine(`[AxonBridge] package version: ${context.extension.packageJSON?.version ?? 'unknown'}`);
        activationOutput.appendLine(`[AxonBridge] extensionUri: ${String(context.extensionUri)}`);

        context.subscriptions.push(activationOutput);

        // Create UI components
        statusBar = new StatusBar();
        context.subscriptions.push({ dispose: () => statusBar.dispose() });

        // Side bar views
        // Note: The callbacks for setup/chat providers are safe because connectionManager
        // is initialized later in this function, and the callbacks are executed lazily.
        const logsViewProvider = new BridgeLogsViewProvider();
        const setupViewProvider = new AxonSetupViewProvider(context, () => connectionManager?.getClient() ?? undefined);
        const chatViewProvider = new AxonChatViewProvider(context, () => connectionManager?.getClient() ?? undefined);

        activationOutput.appendLine(`[AxonBridge] Registering views: ${[
            BridgeLogsViewProvider.viewType,
            AxonSetupViewProvider.viewType,
            AxonChatViewProvider.viewType,
        ].join(', ')}`);

        // Register views
        context.subscriptions.push(
            vscode.window.registerWebviewViewProvider(BridgeLogsViewProvider.viewType, logsViewProvider, {
                webviewOptions: { retainContextWhenHidden: true },
            }),
            vscode.window.registerWebviewViewProvider(AxonSetupViewProvider.viewType, setupViewProvider, {
                webviewOptions: { retainContextWhenHidden: true },
            }),
            vscode.window.registerWebviewViewProvider(AxonChatViewProvider.viewType, chatViewProvider, {
                webviewOptions: { retainContextWhenHidden: true },
            })
        );
        activationOutput.appendLine('[AxonBridge] registered WebviewViewProviders successfully');

        // Initialize connection manager
        activationOutput.appendLine('[AxonBridge] Initializing Connection Manager...');
        connectionManager = BridgeConnectionManager.initialize(statusBar);
        context.subscriptions.push({ dispose: () => connectionManager.dispose() });

        // Register commands
        registerCommands(context, logsViewProvider);

        // Auto-start based on mode and settings
        const config = vscode.workspace.getConfiguration('axonBridge');
        if (config.get('autoConnect', true)) {
            activationOutput.appendLine('[AxonBridge] Auto-connecting in 1s...');
            // Delay slightly to let VS Code finish loading
            setTimeout(() => {
                connectionManager.start().catch(err => {
                    console.error('[AxonBridge] Auto-connect failed:', err);
                    activationOutput.appendLine(`[AxonBridge] Auto-connect failed: ${err}`);
                });
            }, 1000);
        }

        console.log('[AxonBridge] Extension activated');
        activationOutput.appendLine('[AxonBridge] Extension activated successfully');
    } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error(`[AxonBridge] CRITICAL ACTIVATION ERROR: ${msg}`, e);

        // Try to notify user even if output channel failed
        vscode.window.showErrorMessage(`Axon Bridge Extension failed to activate: ${msg}`);
    }
}

function registerCommands(context: vscode.ExtensionContext, logsViewProvider: BridgeLogsViewProvider) {
    // Connect (Local Mode)
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.connect', () => {
            const mode = connectionManager.getMode();
            if (mode === 'local') {
                connectionManager.getClient()?.connect();
            } else {
                vscode.window.showWarningMessage('Connect command only works in Local Mode. Use "Start Server" for Remote Mode.');
            }
        })
    );

    // Disconnect (Local Mode)
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.disconnect', () => {
            const mode = connectionManager.getMode();
            if (mode === 'local') {
                connectionManager.getClient()?.disconnect();
            } else {
                vscode.window.showWarningMessage('Disconnect command only works in Local Mode. Use "Stop Server" for Remote Mode.');
            }
        })
    );

    // Start Server (Remote Mode)
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.startServer', async () => {
            const config = vscode.workspace.getConfiguration('axonBridge');
            const mode = config.get<BridgeMode>('mode', 'local');

            if (mode !== 'remote') {
                const result = await vscode.window.showWarningMessage(
                    'Starting server will switch to Remote Mode. Continue?',
                    'Yes', 'No'
                );
                if (result !== 'Yes') return;

                // Switch to remote mode
                await config.update('mode', 'remote', vscode.ConfigurationTarget.Global);
            }

            await connectionManager.setMode('remote');
            await connectionManager.start();
        })
    );

    // Stop Server (Remote Mode)
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.stopServer', async () => {
            const server = connectionManager.getServer();
            if (server?.isRunning()) {
                await server.stop();
            } else {
                vscode.window.showInformationMessage('Server is not running');
            }
        })
    );

    // Show Server Address
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.showServerAddress', () => {
            const server = connectionManager.getServer();
            if (server?.isRunning()) {
                const port = connectionManager.getServerPort();

                // Get local IP addresses
                const networkInterfaces = require('os').networkInterfaces();
                const addresses: string[] = [];

                for (const name of Object.keys(networkInterfaces)) {
                    for (const iface of networkInterfaces[name]) {
                        if (iface.family === 'IPv4' && !iface.internal) {
                            addresses.push(`ws://${iface.address}:${port}`);
                        }
                    }
                }

                const message = addresses.length > 0
                    ? `Server addresses:\n${addresses.join('\n')}`
                    : `Server listening on port ${port}`;

                vscode.window.showInformationMessage(message, { modal: true });
            } else {
                vscode.window.showInformationMessage('Server is not running. Start it first.');
            }
        })
    );

    // Switch Mode
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.switchMode', async () => {
            const currentMode = connectionManager.getMode();
            const items: vscode.QuickPickItem[] = [
                {
                    label: 'Local Mode',
                    description: currentMode === 'local' ? '(current)' : '',
                    detail: 'VS Code connects to Axon running locally'
                },
                {
                    label: 'Remote Mode',
                    description: currentMode === 'remote' ? '(current)' : '',
                    detail: 'VS Code acts as server, Axon connects over LAN'
                }
            ];

            const selected = await vscode.window.showQuickPick(items, {
                placeHolder: 'Select connection mode'
            });

            if (selected) {
                const newMode: BridgeMode = selected.label === 'Local Mode' ? 'local' : 'remote';
                if (newMode !== currentMode) {
                    await connectionManager.setMode(newMode);
                    vscode.window.showInformationMessage(`Switched to ${selected.label}`);
                }
            }
        })
    );

    // Status
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.status', () => {
            const status = connectionManager.getStatus();
            const mode = connectionManager.getMode();
            vscode.window.showInformationMessage(`Axon Bridge [${mode}]: ${status}`);
        })
    );

    // Logs
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.logs', async () => {
            logsViewProvider.reveal();
            BridgeLogService.shared.showOutput();
        })
    );

    // Clear Logs
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.logs.clear', () => {
            BridgeLogService.shared.clear();
        })
    );
}

export function deactivate() {
    console.log('[AxonBridge] Extension deactivating...');

    if (connectionManager) {
        connectionManager.dispose();
    }

    if (statusBar) {
        statusBar.dispose();
    }
}
