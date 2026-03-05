/**
 * StatusBar.ts
 *
 * Manages the VS Code status bar item showing bridge connection status.
 * Supports both Local Mode (client) and Remote Mode (server) states.
 */

import * as vscode from 'vscode';

export type ConnectionState =
    | 'disconnected'
    | 'connecting'
    | 'connected'
    | 'server_listening'
    | 'server_connected';

export class StatusBar {
    private statusBarItem: vscode.StatusBarItem;
    private state: ConnectionState = 'disconnected';
    private details?: string;

    constructor() {
        this.statusBarItem = vscode.window.createStatusBarItem(
            vscode.StatusBarAlignment.Right,
            100
        );
        this.statusBarItem.command = 'axon-bridge.status';
        this.update();
        this.statusBarItem.show();
    }

    /**
     * Update the status bar based on connection state
     * @param state The connection state
     * @param details Additional details (workspace name, client count, etc.)
     */
    setState(state: ConnectionState, details?: string) {
        this.state = state;
        this.details = details;
        this.update();
    }

    private update() {
        switch (this.state) {
            case 'disconnected':
                this.statusBarItem.text = '$(plug) Axon: Disconnected';
                this.statusBarItem.tooltip = 'Click to show status';
                this.statusBarItem.backgroundColor = undefined;
                break;

            case 'connecting':
                this.statusBarItem.text = '$(sync~spin) Axon: Connecting...';
                this.statusBarItem.tooltip = 'Attempting to connect to Axon...';
                this.statusBarItem.backgroundColor = undefined;
                break;

            case 'connected':
                this.statusBarItem.text = '$(radio-tower) Axon: Connected';
                this.statusBarItem.tooltip = this.details
                    ? `Connected to Axon as "${this.details}"`
                    : 'Connected to Axon';
                this.statusBarItem.backgroundColor = new vscode.ThemeColor(
                    'statusBarItem.prominentBackground'
                );
                break;

            case 'server_listening':
                this.statusBarItem.text = '$(broadcast) Axon: Listening';
                this.statusBarItem.tooltip = 'Server running, waiting for Axon to connect';
                this.statusBarItem.backgroundColor = undefined;
                break;

            case 'server_connected':
                const clientInfo = this.details || 'Axon';
                this.statusBarItem.text = `$(broadcast) Axon: ${clientInfo}`;
                this.statusBarItem.tooltip = `Server mode: ${clientInfo} connected`;
                this.statusBarItem.backgroundColor = new vscode.ThemeColor(
                    'statusBarItem.prominentBackground'
                );
                break;
        }
    }

    /**
     * Show a quick notification
     */
    showNotification(message: string, type: 'info' | 'warning' | 'error' = 'info') {
        switch (type) {
            case 'info':
                vscode.window.showInformationMessage(`Axon Bridge: ${message}`);
                break;
            case 'warning':
                vscode.window.showWarningMessage(`Axon Bridge: ${message}`);
                break;
            case 'error':
                vscode.window.showErrorMessage(`Axon Bridge: ${message}`);
                break;
        }
    }

    dispose() {
        this.statusBarItem.dispose();
    }
}
