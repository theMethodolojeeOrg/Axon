/**
 * BridgeConnectionManager.ts
 *
 * Unified interface for Bridge connections in VS Code.
 * Manages either BridgeClient (Local Mode) or BridgeServer (Remote Mode) based on settings.
 */

import * as vscode from 'vscode';
import { BridgeClient } from './BridgeClient';
import { BridgeServer } from './BridgeServer';
import { StatusBar } from './ui/StatusBar';
import { BridgeMode } from './Protocol';

export class BridgeConnectionManager {
    private static _instance: BridgeConnectionManager | null = null;

    private statusBar: StatusBar;
    private client: BridgeClient | null = null;
    private server: BridgeServer | null = null;
    private mode: BridgeMode = 'local';

    // Event emitter for connection state changes
    private _onConnectionChange = new vscode.EventEmitter<{
        connected: boolean;
        mode: BridgeMode;
    }>();
    readonly onConnectionChange = this._onConnectionChange.event;

    private constructor(statusBar: StatusBar) {
        this.statusBar = statusBar;
        this.loadMode();

        // Watch for configuration changes
        vscode.workspace.onDidChangeConfiguration(e => {
            if (e.affectsConfiguration('axonBridge.mode')) {
                this.loadMode();
            }
        });
    }

    /**
     * Initialize the connection manager (call once from extension.ts)
     */
    static initialize(statusBar: StatusBar): BridgeConnectionManager {
        if (!BridgeConnectionManager._instance) {
            BridgeConnectionManager._instance = new BridgeConnectionManager(statusBar);
        }
        return BridgeConnectionManager._instance;
    }

    /**
     * Get the singleton instance
     */
    static get shared(): BridgeConnectionManager {
        if (!BridgeConnectionManager._instance) {
            throw new Error('BridgeConnectionManager not initialized. Call initialize() first.');
        }
        return BridgeConnectionManager._instance;
    }

    private loadMode() {
        const config = vscode.workspace.getConfiguration('axonBridge');
        const newMode = config.get<BridgeMode>('mode', 'local');

        if (newMode !== this.mode) {
            console.log(`[BridgeConnectionManager] Mode changed from ${this.mode} to ${newMode}`);
            this.mode = newMode;
        }
    }

    /**
     * Get the current connection mode
     */
    getMode(): BridgeMode {
        return this.mode;
    }

    /**
     * Start the bridge based on current mode
     */
    async start(): Promise<void> {
        await this.stop(); // Stop any existing connection first

        if (this.mode === 'local') {
            await this.startClientMode();
        } else {
            await this.startServerMode();
        }
    }

    /**
     * Stop the bridge
     */
    async stop(): Promise<void> {
        if (this.client) {
            this.client.disconnect();
            this.client = null;
        }

        if (this.server) {
            await this.server.stop();
            this.server = null;
        }
    }

    /**
     * Check if connected (or listening in server mode)
     */
    isConnected(): boolean {
        if (this.mode === 'local') {
            return this.client?.isConnected() ?? false;
        } else {
            return this.server?.isRunning() ?? false;
        }
    }

    /**
     * Get status string for display
     */
    getStatus(): string {
        if (this.mode === 'local') {
            return this.client?.getStatus() ?? 'Not started';
        } else {
            if (this.server?.isRunning()) {
                const count = this.server.getClientCount();
                if (count > 0) {
                    return `Server: ${count} client(s) connected`;
                }
                return `Server listening on port ${this.getServerPort()}`;
            }
            return 'Server not running';
        }
    }

    /**
     * Switch connection mode
     */
    async setMode(newMode: BridgeMode): Promise<void> {
        if (newMode === this.mode) return;

        // Update configuration
        const config = vscode.workspace.getConfiguration('axonBridge');
        await config.update('mode', newMode, vscode.ConfigurationTarget.Global);

        this.mode = newMode;

        // Restart with new mode
        await this.start();
    }

    // MARK: - Local Mode (Client)

    private async startClientMode(): Promise<void> {
        console.log('[BridgeConnectionManager] Starting in Local Mode (client)');

        if (!this.client) {
            this.client = new BridgeClient(this.statusBar);
        }

        const config = vscode.workspace.getConfiguration('axonBridge');
        const autoConnect = config.get('autoConnect', true);

        if (autoConnect) {
            this.client.connect();
        }
    }

    /**
     * Get the client instance (for Local Mode)
     */
    getClient(): BridgeClient | null {
        return this.client;
    }

    // MARK: - Remote Mode (Server)

    private async startServerMode(): Promise<void> {
        console.log('[BridgeConnectionManager] Starting in Remote Mode (server)');

        if (!this.server) {
            this.server = new BridgeServer(this.statusBar);
        }

        await this.server.start();
    }

    /**
     * Get the server instance (for Remote Mode)
     */
    getServer(): BridgeServer | null {
        return this.server;
    }

    /**
     * Get the server port (for display)
     */
    getServerPort(): number {
        const config = vscode.workspace.getConfiguration('axonBridge');
        return config.get('serverPort', 8082);
    }

    /**
     * Get the server address for display
     */
    getServerAddress(): string {
        return this.server?.getServerAddress() ?? 'Not running';
    }

    // MARK: - Cleanup

    dispose() {
        this.stop();
        this._onConnectionChange.dispose();
    }
}
