/**
 * BridgeServer.ts
 *
 * WebSocket server for Remote Mode.
 * In Remote Mode, VS Code acts as the server and Axon connects to it.
 * This enables controlling VS Code from a phone over LAN.
 */

import * as vscode from 'vscode';
import * as http from 'http';
import * as https from 'https';
import * as crypto from 'crypto';
import WebSocket, { WebSocketServer } from 'ws';
import {
    BridgeRequest,
    BridgeResponse,
    BridgeHello,
    BridgeWelcome,
    BridgeMode,
    isRequest,
    isResponse,
    createResponse,
    createError,
    createWelcomeFromVSCode,
    getEffectiveMode,
    BridgeErrorCode,
} from './Protocol';
import { FileHandler } from './handlers/FileHandler';
import { TerminalHandler } from './handlers/TerminalHandler';
import { WorkspaceHandler } from './handlers/WorkspaceHandler';
import { StatusBar, ConnectionState } from './ui/StatusBar';
import { BridgeLogService } from './BridgeLogService';
import { BridgeLogsViewProvider } from './ui/BridgeLogsViewProvider';
import { ensureCertificate, formatFingerprint } from './TLSConfig';

const EXTENSION_VERSION = '0.1.0';

interface ConnectedClient {
    id: string;
    socket: WebSocket;
    sessionId: string | null;
    deviceName: string | null;
    connectedAt: Date;
}

export class BridgeServer {
    private wss: WebSocketServer | null = null;
    private httpServer: http.Server | https.Server | null = null;
    private statusBar: StatusBar;

    // Connected clients
    private clients: Map<string, ConnectedClient> = new Map();

    // Handlers
    private fileHandler: FileHandler;
    private terminalHandler: TerminalHandler;
    private workspaceHandler: WorkspaceHandler;

    // Configuration
    private port: number = 8082;
    private host: string = '0.0.0.0';
    private pairingToken: string = '';
    private tlsEnabled: boolean = false;

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
        this.port = config.get('serverPort', 8082);
        this.host = config.get('serverBindAddress', '0.0.0.0');
        this.pairingToken = config.get('pairingToken', '');
        this.tlsEnabled = config.get('tlsEnabled', false);
    }

    /**
     * Start the WebSocket server
     */
    async start(): Promise<void> {
        if (this.wss) {
            console.log('[AxonBridge Server] Already running');
            return;
        }

        // Create HTTP or HTTPS server depending on TLS setting
        if (this.tlsEnabled) {
            console.log('[AxonBridge Server] TLS enabled — generating/loading certificate...');
            const cert = await ensureCertificate();
            this.httpServer = https.createServer({
                cert: Buffer.from(cert.cert),
                key: Buffer.from(cert.key),
            });

            const fp = formatFingerprint(cert.fingerprint);
            console.log(`[AxonBridge Server] TLS certificate fingerprint: ${fp}`);
            this.statusBar.showNotification(`TLS enabled — fingerprint: ${fp.substring(0, 23)}…`);
        } else {
            this.httpServer = http.createServer();
        }

        return new Promise((resolve, reject) => {
            try {
                // Create WebSocket server on top of the HTTP(S) server
                this.wss = new WebSocketServer({
                    server: this.httpServer!,
                });

                this.wss.on('connection', (socket, req) => {
                    this.handleNewConnection(socket, req);
                });

                this.wss.on('error', (error) => {
                    console.error('[AxonBridge Server] WebSocket server error:', error);
                    this.statusBar.showNotification(`Server error: ${error.message}`, 'error');
                });

                const scheme = this.tlsEnabled ? 'wss' : 'ws';

                // Start listening
                this.httpServer!.listen(this.port, this.host, () => {
                    console.log(`[AxonBridge Server] Listening on ${scheme}://${this.host}:${this.port}`);
                    this.statusBar.setState('server_listening');
                    this.statusBar.showNotification(`Server listening on ${scheme}://…:${this.port}`);
                    resolve();
                });

                this.httpServer!.on('error', (error: NodeJS.ErrnoException) => {
                    console.error('[AxonBridge Server] HTTP server error:', error);
                    if (error.code === 'EADDRINUSE') {
                        this.statusBar.showNotification(`Port ${this.port} is already in use`, 'error');
                    }
                    reject(error);
                });

            } catch (error) {
                console.error('[AxonBridge Server] Failed to start:', error);
                reject(error);
            }
        });
    }

    /**
     * Stop the WebSocket server
     */
    async stop(): Promise<void> {
        // Close all client connections
        for (const client of this.clients.values()) {
            try {
                client.socket.close(1000, 'Server shutting down');
            } catch (e) {
                // Ignore
            }
        }
        this.clients.clear();

        // Close WebSocket server
        if (this.wss) {
            this.wss.close();
            this.wss = null;
        }

        // Close HTTP server
        if (this.httpServer) {
            await new Promise<void>((resolve) => {
                this.httpServer!.close(() => resolve());
            });
            this.httpServer = null;
        }

        this.statusBar.setState('disconnected');
        console.log('[AxonBridge Server] Stopped');
    }

    /**
     * Check if server is running
     */
    isRunning(): boolean {
        return this.wss !== null;
    }

    /**
     * Get the number of connected clients
     */
    getClientCount(): number {
        return this.clients.size;
    }

    /**
     * Get server address for display
     */
    getServerAddress(): string {
        if (!this.isRunning()) {
            return 'Not running';
        }
        const scheme = this.tlsEnabled ? 'wss' : 'ws';
        // Show actual IP for LAN access
        return `${scheme}://<your-ip>:${this.port}`;
    }

    // MARK: - Connection Handling

    private handleNewConnection(socket: WebSocket, req: http.IncomingMessage) {
        const clientId = crypto.randomUUID();
        const clientIP = req.socket.remoteAddress || 'unknown';

        console.log(`[AxonBridge Server] New connection from ${clientIP} (clientId: ${clientId.substring(0, 8)})`);

        const client: ConnectedClient = {
            id: clientId,
            socket,
            sessionId: null,
            deviceName: null,
            connectedAt: new Date(),
        };

        this.clients.set(clientId, client);

        socket.on('message', (data: WebSocket.Data) => {
            const text = data.toString();

            // Log incoming traffic
            BridgeLogService.shared.logIncoming(text);
            BridgeLogsViewProvider.shared?.notifyNewEntry();

            this.handleMessage(clientId, text);
        });

        socket.on('close', (code: number, reason: Buffer) => {
            console.log(`[AxonBridge Server] Client disconnected: ${clientId.substring(0, 8)} (code: ${code})`);
            this.clients.delete(clientId);
            this.updateStatusBar();
        });

        socket.on('error', (error: Error) => {
            console.error(`[AxonBridge Server] Client error (${clientId.substring(0, 8)}):`, error.message);
            this.clients.delete(clientId);
            this.updateStatusBar();
        });
    }

    private handleMessage(clientId: string, data: string) {
        const client = this.clients.get(clientId);
        if (!client) return;

        try {
            const message = JSON.parse(data);

            if (isRequest(message)) {
                this.handleRequest(client, message);
            } else if (isResponse(message)) {
                // In Remote Mode, we don't expect responses from Axon
                // Axon is the puppeteer and only sends requests
                console.log(`[AxonBridge Server] Unexpected response from Axon: ${message.id}`);
            } else {
                console.log('[AxonBridge Server] Received notification:', message);
            }
        } catch (error) {
            console.error('[AxonBridge Server] Failed to parse message:', error);
        }
    }

    private async handleRequest(client: ConnectedClient, request: BridgeRequest) {
        console.log(`[AxonBridge Server] Handling request: ${request.method} from ${client.id.substring(0, 8)}`);

        // Handle hello/handshake
        if (request.method === 'hello') {
            this.handleHello(client, request);
            return;
        }

        // All other requests require an established session
        if (!client.sessionId) {
            const error = createError(BridgeErrorCode.InvalidRequest, 'Handshake required before sending requests');
            this.sendResponse(client, createResponse(request.id, undefined, error));
            return;
        }

        // Route to appropriate handler
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
        this.sendResponse(client, response);
    }

    private handleHello(client: ConnectedClient, request: BridgeRequest) {
        const hello = request.params as BridgeHello;

        // Validate pairing token if required
        if (this.pairingToken.trim()) {
            const presentedToken = (hello.pairingToken ?? '').trim();
            if (presentedToken !== this.pairingToken.trim()) {
                console.log(`[AxonBridge Server] Pairing token mismatch from ${client.id.substring(0, 8)}`);
                const error = createError(
                    BridgeErrorCode.InvalidRequest,
                    'Pairing token mismatch. Set axonBridge.pairingToken in VS Code to match Axon.'
                );
                this.sendResponse(client, createResponse(request.id, undefined, error));
                client.socket.close(1008, 'Authentication failed');
                return;
            }
        }

        // Create session
        const sessionId = crypto.randomUUID();
        client.sessionId = sessionId;
        client.deviceName = hello.deviceName ?? 'Axon';

        console.log(`[AxonBridge Server] Axon connected: ${client.deviceName} (session: ${sessionId.substring(0, 8)})`);

        // Get workspace info for welcome response
        const folders = vscode.workspace.workspaceFolders;
        const workspaceRoot = folders?.[0]?.uri.fsPath ?? '';
        const workspaceName = vscode.workspace.name ?? folders?.[0]?.name ?? 'Unknown';

        // Generate workspace ID
        const workspaceId = 'sha256:' + crypto.createHash('sha256')
            .update(workspaceRoot)
            .digest('hex')
            .substring(0, 16);

        // Send welcome response
        const welcome = createWelcomeFromVSCode({
            sessionId,
            extensionVersion: EXTENSION_VERSION,
            workspaceId,
            workspaceName,
            workspaceRoot,
            capabilities: [
                'file/read',
                'file/write',
                'file/list',
                'terminal/run',
                'workspace/info',
            ],
            supportedMethods: [
                'hello',
                'file/read',
                'file/write',
                'file/list',
                'terminal/run',
                'workspace/info',
            ],
        });

        this.sendResponse(client, createResponse(request.id, welcome));
        this.updateStatusBar();
        this.statusBar.showNotification(`${client.deviceName} connected`);
    }

    private sendResponse(client: ConnectedClient, response: BridgeResponse) {
        if (client.socket.readyState !== WebSocket.OPEN) {
            console.error('[AxonBridge Server] Cannot send: socket not open');
            return;
        }

        const data = JSON.stringify(response);

        // Log outgoing traffic
        BridgeLogService.shared.logOutgoing(data);
        BridgeLogsViewProvider.shared?.notifyNewEntry();

        client.socket.send(data);
    }

    private updateStatusBar() {
        const clientCount = this.clients.size;
        const connectedClients = Array.from(this.clients.values()).filter(c => c.sessionId);

        if (connectedClients.length > 0) {
            const names = connectedClients.map(c => c.deviceName).join(', ');
            this.statusBar.setState('connected', `${names} (${connectedClients.length})`);
        } else if (this.isRunning()) {
            this.statusBar.setState('server_listening');
        } else {
            this.statusBar.setState('disconnected');
        }
    }

    // MARK: - Cleanup

    dispose() {
        this.stop();
    }
}
