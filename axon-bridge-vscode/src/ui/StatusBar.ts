/**
 * StatusBar.ts
 *
 * Manages the VS Code status bar item showing bridge connection status.
 */

import * as vscode from 'vscode';

export type ConnectionState = 'disconnected' | 'connecting' | 'connected';

export class StatusBar {
    private statusBarItem: vscode.StatusBarItem;
    private state: ConnectionState = 'disconnected';
    private workspaceName?: string;

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
     */
    setState(state: ConnectionState, workspaceName?: string) {
        this.state = state;
        this.workspaceName = workspaceName;
        this.update();
    }

    private update() {
        switch (this.state) {
            case 'disconnected':
                this.statusBarItem.text = '$(plug) Axon: Disconnected';
                this.statusBarItem.tooltip = 'Click to connect to Axon';
                this.statusBarItem.backgroundColor = undefined;
                break;

            case 'connecting':
                this.statusBarItem.text = '$(sync~spin) Axon: Connecting...';
                this.statusBarItem.tooltip = 'Attempting to connect to Axon...';
                this.statusBarItem.backgroundColor = undefined;
                break;

            case 'connected':
                this.statusBarItem.text = '$(radio-tower) Axon: Connected';
                this.statusBarItem.tooltip = this.workspaceName
                    ? `Connected to Axon as "${this.workspaceName}"`
                    : 'Connected to Axon';
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
