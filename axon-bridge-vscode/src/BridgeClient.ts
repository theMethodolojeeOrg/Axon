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
    BridgePairingInfo,
    ChatListConversationsResult,
    ChatGetMessagesParams,
    ChatGetMessagesResult,
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
import { BridgeLogService } from './BridgeLogService';
import { BridgeLogsViewProvider } from './ui/BridgeLogsViewProvider';

const EXTENSION_VERSION = '0.1.0';

export class BridgeClient {
    private ws: WebSocket | null = null;
    private statusBar: StatusBar;
    private reconnectTimer: NodeJS.Timeout | null = null;
    private isConnecting = false;
    private sessionId: string | null = null;

    private pendingResolvers = new Map<
        string,
        {
            resolve: (value: unknown) => void;
            reject: (err: unknown) => void;
        }
    >();

    // Handlers
    private fileHandler: FileHandler;
    private terminalHandler: TerminalHandler;
    private workspaceHandler: WorkspaceHandler;

    // Configuration
    private host: string = 'localhost';
    private port: number = 8081;
    private autoConnect: boolean = true;
    private reconnectInterval: number = 5000;
    private pairingToken: string = '';
    private tlsEnabled: boolean = false;

    // Exponential backoff state
    private reconnectAttempts: number = 0;
    private readonly maxReconnectInterval: number = 60000; // 1 minute max

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
        this.pairingToken = config.get('pairingToken', '');
        this.tlsEnabled = config.get('tlsEnabled', false);
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

        const scheme = this.tlsEnabled ? 'wss' : 'ws';
        const url = `${scheme}://${this.host}:${this.port}`;
        console.log(`[AxonBridge] Connecting to ${url}...`);

        try {
            // Configure WebSocket options for TLS if needed
            const wsOptions: WebSocket.ClientOptions = {};
            if (this.tlsEnabled) {
                // For self-signed certificates, we might need to disable cert validation
                // In production, proper cert validation should be used
                wsOptions.rejectUnauthorized = false;
            }

            this.ws = new WebSocket(url, wsOptions);

            this.ws.on('open', () => {
                console.log('[AxonBridge] Connection opened');
                this.isConnecting = false;
                this.sendHello();
            });

            this.ws.on('message', (data: WebSocket.Data) => {
                const text = data.toString();

                // Mirror incoming traffic to extension logs
                BridgeLogService.shared.logIncoming(text);
                BridgeLogsViewProvider.shared?.notifyNewEntry();

                this.handleMessage(text);
            });

            this.ws.on('close', (code: number, reason: Buffer) => {
                console.log(`[AxonBridge] Connection closed: ${code} ${reason.toString()}`);
                this.cleanupSocket();
                this.handleDisconnect();
            });

            this.ws.on('error', (error: Error) => {
                console.error('[AxonBridge] WebSocket error:', error.message);
                this.isConnecting = false;

                // Clean up the failed socket properly to prevent resource leaks
                this.cleanupSocket();

                // Schedule reconnect if autoConnect is enabled
                if (this.autoConnect) {
                    this.scheduleReconnect();
                }
            });
        } catch (error) {
            console.error('[AxonBridge] Failed to create WebSocket:', error);
            this.isConnecting = false;
            this.cleanupSocket();

            if (this.autoConnect) {
                this.scheduleReconnect();
            }
        }
    }

    /**
     * Clean up WebSocket resources properly
     */
    private cleanupSocket() {
        if (this.ws) {
            // Remove all listeners to prevent memory leaks and zombie handlers
            this.ws.removeAllListeners();

            // Close if still open (use try-catch in case already closed)
            try {
                if (this.ws.readyState === WebSocket.OPEN ||
                    this.ws.readyState === WebSocket.CONNECTING) {
                    this.ws.close();
                }
            } catch (e) {
                // Ignore close errors
            }

            this.ws = null;
        }
    }

    /**
     * Disconnect from the bridge
     */
    disconnect() {
        this.cancelReconnect();
        this.reconnectAttempts = 0;

        if (this.ws) {
            try {
                this.ws.close(1000, 'User requested disconnect');
            } catch (e) {
                // Ignore
            }
        }

        this.cleanupSocket();
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
        } else if (this.reconnectTimer) {
            return `Disconnected (reconnecting in ${this.getNextReconnectDelay() / 1000}s)`;
        } else {
            return 'Disconnected';
        }
    }

    /**
     * Calculate the next reconnect delay with exponential backoff
     */
    private getNextReconnectDelay(): number {
        return Math.min(
            this.reconnectInterval * Math.pow(2, this.reconnectAttempts),
            this.maxReconnectInterval
        );
    }

    // MARK: - Message Handling

    private sendHello() {
        // Reset reconnect attempts on successful connection
        this.reconnectAttempts = 0;

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
            pairingToken: this.pairingToken?.trim() ? this.pairingToken.trim() : undefined,
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
        // Resolve any pending request promise first
        const pending = this.pendingResolvers.get(response.id);
        if (pending) {
            this.pendingResolvers.delete(response.id);
            if (response.error) {
                pending.reject(new Error(response.error.message));
            } else {
                pending.resolve(response.result);
            }
            return;
        }

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
                case 'ping':
                    // Simple ping-pong for connectivity testing
                    result = {
                        message: (request.params as { message?: string })?.message ?? 'pong',
                        ts: Date.now(),
                    };
                    break;

                case 'file/read':
                case 'readFile': // Alias for more intuitive naming
                    result = await this.fileHandler.read(request.params as any);
                    break;

                case 'file/write':
                case 'writeFile': // Alias for more intuitive naming
                    result = await this.fileHandler.write(request.params as any);
                    break;

                case 'file/list':
                case 'listFiles': // Alias for more intuitive naming
                    result = await this.fileHandler.list(request.params as any);
                    break;

                case 'terminal/run':
                case 'runTerminal': // Alias for more intuitive naming
                    result = await this.terminalHandler.run(request.params as any);
                    break;

                case 'workspace/info':
                case 'workspaceInfo': // Alias for more intuitive naming
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

        // Mirror outgoing traffic to extension logs
        BridgeLogService.shared.logOutgoing(data);
        BridgeLogsViewProvider.shared?.notifyNewEntry();

        this.ws.send(data);
    }

    // MARK: - Axon Setup + Chat Mirror (read-only)

    async getPairingInfo(): Promise<BridgePairingInfo> {
        return await this.sendRequestAndWaitForResult<BridgePairingInfo>('bridge/getPairingInfo');
    }

    async chatListConversations(): Promise<ChatListConversationsResult> {
        return await this.sendRequestAndWaitForResult<ChatListConversationsResult>('chat/listConversations');
    }

    async chatGetMessages(params: ChatGetMessagesParams): Promise<ChatGetMessagesResult> {
        return await this.sendRequestAndWaitForResult<ChatGetMessagesResult>('chat/getMessages', params);
    }

    private sendRequestAndWaitForResult<T>(method: string, params?: unknown, timeoutMs: number = 15000): Promise<T> {
        return new Promise<T>((resolve, reject) => {
            if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
                reject(new Error('Not connected'));
                return;
            }

            const id = `${method}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const request: BridgeRequest = { jsonrpc: '2.0', id, method, params };

            const timer = setTimeout(() => {
                this.pendingResolvers.delete(id);
                reject(new Error(`Request timed out: ${method}`));
            }, timeoutMs);

            this.pendingResolvers.set(id, {
                resolve: (value: unknown) => {
                    clearTimeout(timer);
                    resolve(value as T);
                },
                reject: (err: unknown) => {
                    clearTimeout(timer);
                    reject(err instanceof Error ? err : new Error(String(err)));
                }
            });

            this.send(request);
        });
    }

    // MARK: - Reconnection

    private handleDisconnect() {
        this.isConnecting = false;
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

        // Exponential backoff: 5s, 10s, 20s, 40s, 60s max
        const delay = this.getNextReconnectDelay();
        this.reconnectAttempts++;

        console.log(`[AxonBridge] Scheduling reconnect in ${delay}ms (attempt ${this.reconnectAttempts})...`);

        this.reconnectTimer = setTimeout(() => {
            this.reconnectTimer = null;
            this.connect();
        }, delay);
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
        this.cleanupSocket();
    }
}
