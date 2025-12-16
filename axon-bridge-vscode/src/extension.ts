/**
 * extension.ts
 *
 * Entry point for the Axon Bridge VS Code extension.
 * Connects VS Code to Axon as a "puppet" - receiving commands to execute
 * file operations, terminal commands, and workspace queries.
 */

import * as vscode from 'vscode';
import { BridgeClient } from './BridgeClient';
import { StatusBar } from './ui/StatusBar';
import { BridgeLogService } from './BridgeLogService';
import { BridgeLogsViewProvider } from './ui/BridgeLogsViewProvider';

let client: BridgeClient;
let statusBar: StatusBar;

export function activate(context: vscode.ExtensionContext) {
    console.log('[AxonBridge] Extension activating...');

    // Create UI components
    statusBar = new StatusBar();
    context.subscriptions.push({ dispose: () => statusBar.dispose() });

    // Side bar logs view
    const logsViewProvider = new BridgeLogsViewProvider();
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider(BridgeLogsViewProvider.viewType, logsViewProvider, {
            webviewOptions: { retainContextWhenHidden: true },
        })
    );

    // Create bridge client
    client = new BridgeClient(statusBar);
    context.subscriptions.push({ dispose: () => client.dispose() });

    // Register commands
    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.connect', () => {
            client.connect();
        })
    );

    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.disconnect', () => {
            client.disconnect();
        })
    );

    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.status', () => {
            const status = client.getStatus();
            vscode.window.showInformationMessage(`Axon Bridge: ${status}`);
        })
    );

    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.logs', async () => {
            logsViewProvider.reveal();
            BridgeLogService.shared.showOutput();
        })
    );

    context.subscriptions.push(
        vscode.commands.registerCommand('axon-bridge.logs.clear', () => {
            BridgeLogService.shared.clear();
        })
    );

    // Auto-connect if enabled
    const config = vscode.workspace.getConfiguration('axonBridge');
    if (config.get('autoConnect', true)) {
        // Delay slightly to let VS Code finish loading
        setTimeout(() => {
            client.connect();
        }, 1000);
    }

    console.log('[AxonBridge] Extension activated');
}

export function deactivate() {
    console.log('[AxonBridge] Extension deactivating...');

    if (client) {
        client.dispose();
    }

    if (statusBar) {
        statusBar.dispose();
    }
}
