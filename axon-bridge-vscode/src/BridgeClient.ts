/**
 * BridgeClient.ts
 *
 * WebSocket client that connects to Axon and handles message dispatch.
 * Axon is the "puppeteer" (server), this extension is the "puppet" (client).
 */

import * as vscode from 'vscode';
import WebSocket from 'ws';
import * as crypto from 'crypto';
import {
    BridgeRequest,
    BridgeResponse,
    BridgeHello,
    BridgeWelcome,
    isRequest,
    isResponse,
    createResponse,
    createError,
    BridgeErrorCode,
} from './Protocol';
import { FileHandler } from './handlers/FileHandler';
import { TerminalHandler } from './handlers/TerminalHandler';
import { WorkspaceHandler } from './handlers/WorkspaceHandler';
import { StatusBar, ConnectionState } from './ui/StatusBar';

const EXTENSION_VERSION = '0.1.0';

export class BridgeClient {
    private ws: WebSocket | null = null;
    private statusBar: StatusBar;
    private reconnectTimer: NodeJS.Timeout | null = null;
    private isConnecting = false;
    private sessionId: string | null = null;

    // Handlers
    private fileHandler: FileHandler;
    private terminalHandler: TerminalHandler;
    private workspaceHandler: WorkspaceHandler;

    // Configuration
    private host: string = 'localhost';
    private port: number = 8081;
    private autoConnect: boolean = true;
    private reconnectInterval: number = 5000;

    constructor(statusBar: StatusBar) {
        this.statusBar = statusBar;
        this.fileHandler = new FileHandler();
        this.terminalHandler = new TerminalHandler();
        this.workspaceHandler = new WorkspaceHandler();

        // Load configuration
        this.loadConfiguration();

        // Watch for configuration changes
        vscode.workspace.onDidChangeConfiguration(e => {
            if (e.affectsConfiguration('axonBridge')) {
                this.loadConfiguration();
            }
        });
    }

    private loadConfiguration() {
        const config = vscode.workspace.getConfiguration('axonBridge');
        this.host = config.get('host', 'localhost');
        this.port = config.get('port', 8081);
        this.autoConnect = config.get('autoConnect', true);
        this.reconnectInterval = config.get('reconnectInterval', 5000);
    }

    /**
     * Connect to the Axon bridge server
     */
    connect() {
        if (this.isConnecting || this.isConnected()) {
            return;
        }

        this.isConnecting = true;
        this.statusBar.setState('connecting');

        const url = `ws://${this.host}:${this.port}`;
        console.log(`[AxonBridge] Connecting to ${url}...`);

        try {
            this.ws = new WebSocket(url);

            this.ws.on('open', () => {
                console.log('[AxonBridge] Connection opened');
                this.isConnecting = false;
                this.sendHello();
            });

            this.ws.on('message', (data: WebSocket.Data) => {
                this.handleMessage(data.toString());
            });

            this.ws.on('close', (code: number, reason: Buffer) => {
                console.log(`[AxonBridge] Connection closed: ${code} ${reason.toString()}`);
                this.handleDisconnect();
            });

            this.ws.on('error', (error: Error) => {
                console.error('[AxonBridge] WebSocket error:', error.message);
                this.isConnecting = false;
                // Don't show notification for connection errors during auto-connect
                // They'll keep trying silently
            });
        } catch (error) {
            console.error('[AxonBridge] Failed to create WebSocket:', error);
            this.isConnecting = false;
            this.scheduleReconnect();
        }
    }

    /**
     * Disconnect from the bridge
     */
    disconnect() {
        this.cancelReconnect();

        if (this.ws) {
            this.ws.close(1000, 'User requested disconnect');
            this.ws = null;
        }

        this.sessionId = null;
        this.statusBar.setState('disconnected');
        this.statusBar.showNotification('Disconnected from Axon');
    }

    /**
     * Check if connected
     */
    isConnected(): boolean {
        return this.ws !== null && this.ws.readyState === WebSocket.OPEN;
    }

    /**
     * Get connection status for display
     */
    getStatus(): string {
        if (this.isConnected()) {
            return `Connected (session: ${this.sessionId?.substring(0, 8) ?? 'unknown'})`;
        } else if (this.isConnecting) {
            return 'Connecting...';
        } else {
            return 'Disconnected';
        }
    }

    // MARK: - Message Handling

    private sendHello() {
        const folders = vscode.workspace.workspaceFolders;
        const workspaceRoot = folders?.[0]?.uri.fsPath ?? '';
        const workspaceName = vscode.workspace.name ?? folders?.[0]?.name ?? 'Unknown';

        // Generate a stable workspace ID from the path
        const workspaceId = crypto.createHash('sha256')
            .update(workspaceRoot)
            .digest('hex')
            .substring(0, 16);

        const hello: BridgeHello = {
            workspaceId: `sha256:${workspaceId}`,
            workspaceName,
            workspaceRoot,
            capabilities: [
                'file/read',
                'file/write',
                'file/list',
                'terminal/run',
                'workspace/info',
            ],
            extensionVersion: EXTENSION_VERSION,
            vscodeVersion: vscode.version,
        };

        // Send as a request (expecting welcome response)
        const request: BridgeRequest = {
            jsonrpc: '2.0',
            id: 'hello',
            method: 'hello',
            params: hello,
        };

        this.send(request);
    }

    private handleMessage(data: string) {
        try {
            const message = JSON.parse(data);

            if (isResponse(message)) {
                this.handleResponse(message);
            } else if (isRequest(message)) {
                this.handleRequest(message);
            } else {
                console.log('[AxonBridge] Received notification:', message);
            }
        } catch (error) {
            console.error('[AxonBridge] Failed to parse message:', error);
        }
    }

    private handleResponse(response: BridgeResponse) {
        // Handle hello response (welcome)
        if (response.id === 'hello') {
            if (response.error) {
                console.error('[AxonBridge] Hello failed:', response.error.message);
                this.statusBar.showNotification(`Connection failed: ${response.error.message}`, 'error');
                this.disconnect();
                return;
            }

            const welcome = response.result as BridgeWelcome;
            this.sessionId = welcome.sessionId;
            this.statusBar.setState('connected', vscode.workspace.name);
            this.statusBar.showNotification('Connected to Axon');
            console.log(`[AxonBridge] Connected! Session: ${this.sessionId}, Axon: ${welcome.axonVersion}`);
        }
    }

    private async handleRequest(request: BridgeRequest) {
        console.log(`[AxonBridge] Handling request: ${request.method}`);

        let result: unknown;
        let error: ReturnType<typeof createError> | undefined;

        try {
            switch (request.method) {
                case 'file/read':
                    result = await this.fileHandler.read(request.params as any);
                    break;

                case 'file/write':
                    result = await this.fileHandler.write(request.params as any);
                    break;

                case 'file/list':
                    result = await this.fileHandler.list(request.params as any);
                    break;

                case 'terminal/run':
                    result = await this.terminalHandler.run(request.params as any);
                    break;

                case 'workspace/info':
                    result = await this.workspaceHandler.getInfo();
                    break;

                default:
                    error = createError(
                        BridgeErrorCode.MethodNotFound,
                        `Unknown method: ${request.method}`
                    );
            }
        } catch (e) {
            if ((e as any).code !== undefined) {
                // It's already a BridgeError
                error = e as ReturnType<typeof createError>;
            } else {
                error = createError(
                    BridgeErrorCode.InternalError,
                    e instanceof Error ? e.message : String(e)
                );
            }
        }

        // Send response
        const response = createResponse(request.id, result, error);
        this.send(response);
    }

    private send(message: BridgeRequest | BridgeResponse) {
        if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
            console.error('[AxonBridge] Cannot send: not connected');
            return;
        }

        const data = JSON.stringify(message);
        this.ws.send(data);
    }

    // MARK: - Reconnection

    private handleDisconnect() {
        this.isConnecting = false;
        this.ws = null;
        this.sessionId = null;
        this.statusBar.setState('disconnected');

        if (this.autoConnect) {
            this.scheduleReconnect();
        }
    }

    private scheduleReconnect() {
        if (this.reconnectTimer) {
            return;
        }

        console.log(`[AxonBridge] Scheduling reconnect in ${this.reconnectInterval}ms...`);

        this.reconnectTimer = setTimeout(() => {
            this.reconnectTimer = null;
            this.connect();
        }, this.reconnectInterval);
    }

    private cancelReconnect() {
        if (this.reconnectTimer) {
            clearTimeout(this.reconnectTimer);
            this.reconnectTimer = null;
        }
    }

    // MARK: - Cleanup

    dispose() {
        this.cancelReconnect();
        if (this.ws) {
            this.ws.close();
            this.ws = null;
        }
    }
}
