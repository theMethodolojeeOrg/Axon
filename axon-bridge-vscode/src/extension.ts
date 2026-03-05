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
import { showCertificateFingerprint } from './TLSConfig';
import { BridgeMode } from './Protocol';
import { ConnectionProfileManager } from './ConnectionProfileManager';
import { TrustedCertManager } from './TrustedCertManager';

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
        const setupViewProvider = new AxonSetupViewProvider(
            context,
            () => connectionManager ?? undefined,
            () => connectionManager?.getClient() ?? undefined,
        );
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

            await connectionManager.enableRemoteNetworking();
        })
    );

    // Stop Server (Remote Mode)
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.stopServer', async () => {
            if (connectionManager.isServerRunning()) {
                await connectionManager.disableRemoteNetworking();
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
                const config = vscode.workspace.getConfiguration('axonBridge');
                const port = connectionManager.getServerPort();
                const tlsEnabled = config.get<boolean>('tlsEnabled', false);
                const scheme = tlsEnabled ? 'wss' : 'ws';

                // Get local IP addresses
                const networkInterfaces = require('os').networkInterfaces();
                const addresses: string[] = [];

                for (const name of Object.keys(networkInterfaces)) {
                    for (const iface of networkInterfaces[name]) {
                        if (iface.family === 'IPv4' && !iface.internal) {
                            addresses.push(`${scheme}://${iface.address}:${port}`);
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

    // Show TLS Certificate Fingerprint
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.showFingerprint', () => {
            showCertificateFingerprint();
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

    // Import Profile (QR Payload)
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.importProfile', async () => {
            const payload = await vscode.window.showInputBox({
                prompt: 'Paste ws:// or wss:// connection URL from Axon',
                placeHolder: 'ws://192.168.1.100:8081?pairingToken=...',
                validateInput: (value) => {
                    if (!value.trim()) return 'Please enter a URL';
                    const parsed = ConnectionProfileManager.parseQRPayload(value);
                    if (!parsed) return 'Invalid ws:// or wss:// URL';
                    return null;
                }
            });
            if (!payload) return;

            const name = await vscode.window.showInputBox({
                prompt: 'Name for this connection profile',
                placeHolder: 'My Axon Host',
            });

            const profile = ConnectionProfileManager.importFromQRPayload(payload, name || undefined);
            if (profile) {
                const parsed = ConnectionProfileManager.parseQRPayload(payload);
                if (parsed?.pairingToken) {
                    const apply = await vscode.window.showQuickPick(['Yes', 'No'], {
                        placeHolder: 'Apply pairing token from URL to global settings?'
                    });
                    if (apply === 'Yes') {
                        const config = vscode.workspace.getConfiguration('axonBridge');
                        await config.update('pairingToken', parsed.pairingToken, vscode.ConfigurationTarget.Global);
                    }
                }
                vscode.window.showInformationMessage(`Imported profile: ${profile.name}`);
            } else {
                vscode.window.showErrorMessage('Failed to import profile from URL.');
            }
        })
    );

    // Connect to Saved Profile
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.connectToProfile', async () => {
            const profiles = ConnectionProfileManager.getProfiles();
            if (profiles.length === 0) {
                const action = await vscode.window.showInformationMessage(
                    'No saved profiles. Import one first.',
                    'Import Profile'
                );
                if (action === 'Import Profile') {
                    vscode.commands.executeCommand('axon-bridge.importProfile');
                }
                return;
            }

            const defaultId = ConnectionProfileManager.getDefaultProfileId();
            const items = profiles.map(p => ({
                label: p.name,
                description: `${p.tlsEnabled ? 'wss' : 'ws'}://${p.host}:${p.port}${p.id === defaultId ? ' (default)' : ''}`,
                detail: p.lastConnectedAt ? `Last connected: ${new Date(p.lastConnectedAt).toLocaleString()}` : 'Never connected',
                profileId: p.id,
            }));

            const selected = await vscode.window.showQuickPick(items, {
                placeHolder: 'Select a profile to connect to'
            });

            if (selected) {
                await connectionManager.connectToProfile(selected.profileId);
            }
        })
    );

    // Manage Profiles
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.manageProfiles', async () => {
            const profiles = ConnectionProfileManager.getProfiles();
            const defaultId = ConnectionProfileManager.getDefaultProfileId();

            const actions: (vscode.QuickPickItem & { action: string; profileId?: string })[] = [
                { label: '$(add) Add Profile Manually', action: 'add' },
                { label: '$(cloud-download) Import from URL', action: 'import' },
            ];

            for (const p of profiles) {
                actions.push({
                    label: p.name,
                    description: `${p.tlsEnabled ? 'wss' : 'ws'}://${p.host}:${p.port}${p.id === defaultId ? ' (default)' : ''}`,
                    action: 'manage',
                    profileId: p.id,
                });
            }

            const selected = await vscode.window.showQuickPick(actions, {
                placeHolder: 'Manage connection profiles'
            });

            if (!selected) return;

            if (selected.action === 'import') {
                vscode.commands.executeCommand('axon-bridge.importProfile');
            } else if (selected.action === 'add') {
                const name = await vscode.window.showInputBox({ prompt: 'Profile name' });
                if (!name) return;
                const host = await vscode.window.showInputBox({ prompt: 'Host or IP address' });
                if (!host) return;
                const portStr = await vscode.window.showInputBox({ prompt: 'Port', value: '8081' });
                if (!portStr) return;
                const port = parseInt(portStr, 10);
                if (isNaN(port) || port < 1 || port > 65535) {
                    vscode.window.showErrorMessage('Invalid port number.');
                    return;
                }
                const tls = await vscode.window.showQuickPick(['No', 'Yes'], { placeHolder: 'Enable TLS (wss://)?' });
                const profile = ConnectionProfileManager.addProfile(name, host, port, tls === 'Yes');
                vscode.window.showInformationMessage(`Created profile: ${profile.name}`);
            } else if (selected.action === 'manage' && selected.profileId) {
                const profile = ConnectionProfileManager.getProfiles().find(p => p.id === selected.profileId);
                if (!profile) return;

                const isDefault = profile.id === defaultId;
                const manageActions = [
                    { label: '$(plug) Connect', action: 'connect' },
                    { label: isDefault ? '$(star-full) Default' : '$(star-empty) Set as Default', action: 'setDefault' },
                    { label: '$(edit) Edit', action: 'edit' },
                    { label: '$(trash) Delete', action: 'delete' },
                ];

                const action = await vscode.window.showQuickPick(manageActions, {
                    placeHolder: `${profile.name} — ${profile.host}:${profile.port}`
                });

                if (!action) return;

                switch (action.action) {
                    case 'connect':
                        await connectionManager.connectToProfile(profile.id);
                        break;
                    case 'setDefault':
                        ConnectionProfileManager.setDefaultProfile(profile.id);
                        vscode.window.showInformationMessage(`${profile.name} set as default.`);
                        break;
                    case 'edit': {
                        const newName = await vscode.window.showInputBox({ prompt: 'Profile name', value: profile.name });
                        if (newName === undefined) return;
                        const newHost = await vscode.window.showInputBox({ prompt: 'Host or IP', value: profile.host });
                        if (newHost === undefined) return;
                        const newPortStr = await vscode.window.showInputBox({ prompt: 'Port', value: String(profile.port) });
                        if (newPortStr === undefined) return;
                        const newPort = parseInt(newPortStr, 10);
                        if (isNaN(newPort) || newPort < 1 || newPort > 65535) {
                            vscode.window.showErrorMessage('Invalid port number.');
                            return;
                        }
                        const newTls = await vscode.window.showQuickPick(['No', 'Yes'], {
                            placeHolder: 'Enable TLS?',
                        });
                        ConnectionProfileManager.updateProfile(profile.id, {
                            name: newName,
                            host: newHost,
                            port: newPort,
                            tlsEnabled: newTls === 'Yes',
                        });
                        vscode.window.showInformationMessage(`Updated profile: ${newName}`);
                        break;
                    }
                    case 'delete': {
                        const confirm = await vscode.window.showWarningMessage(
                            `Delete profile "${profile.name}"?`,
                            { modal: true },
                            'Delete'
                        );
                        if (confirm === 'Delete') {
                            ConnectionProfileManager.deleteProfile(profile.id);
                            vscode.window.showInformationMessage(`Deleted profile: ${profile.name}`);
                        }
                        break;
                    }
                }
            }
        })
    );

    // Manage Trusted Certificates
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.manageTrustedCerts', async () => {
            const fps = TrustedCertManager.getTrustedFingerprints();

            const actions: (vscode.QuickPickItem & { action: string; fingerprint?: string })[] = [
                { label: '$(add) Add Trusted Fingerprint', action: 'add' },
            ];

            for (const fp of fps) {
                actions.push({
                    label: TrustedCertManager.formatFingerprint(fp),
                    description: '',
                    action: 'remove',
                    fingerprint: fp,
                });
            }

            if (fps.length === 0) {
                actions.push({
                    label: 'No trusted fingerprints',
                    description: 'All self-signed certificates will be accepted',
                    action: 'none',
                });
            }

            const selected = await vscode.window.showQuickPick(actions, {
                placeHolder: 'Manage trusted TLS certificate fingerprints'
            });

            if (!selected) return;

            if (selected.action === 'add') {
                const input = await vscode.window.showInputBox({
                    prompt: 'Enter SHA-256 certificate fingerprint (hex)',
                    placeHolder: 'AA:BB:CC:DD:... or aabbccdd...',
                    validateInput: (value) => {
                        const normalized = TrustedCertManager.normalizeFingerprint(value);
                        if (!TrustedCertManager.isValidFingerprint(normalized)) {
                            return 'Invalid fingerprint. Expected 64 hex characters (SHA-256).';
                        }
                        return null;
                    }
                });
                if (input) {
                    if (TrustedCertManager.addTrustedFingerprint(input)) {
                        vscode.window.showInformationMessage('Fingerprint added to trusted list.');
                    } else {
                        vscode.window.showInformationMessage('Fingerprint already trusted or invalid.');
                    }
                }
            } else if (selected.action === 'remove' && selected.fingerprint) {
                const confirm = await vscode.window.showWarningMessage(
                    'Remove this trusted fingerprint?',
                    { modal: true },
                    'Remove'
                );
                if (confirm === 'Remove') {
                    TrustedCertManager.removeTrustedFingerprint(selected.fingerprint);
                    vscode.window.showInformationMessage('Fingerprint removed.');
                }
            }
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
