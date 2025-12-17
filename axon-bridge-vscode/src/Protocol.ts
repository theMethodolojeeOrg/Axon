/**
 * Protocol.ts
 *
 * JSON-RPC 2.0 style protocol definitions for Axon Bridge communication.
 * These types mirror the Swift BridgeProtocol.swift definitions.
 *
 * Supports two connection modes:
 * - Local Mode: Axon is server (default), VS Code connects as client
 * - Remote Mode: VS Code is server, Axon connects as client (for LAN access)
 */

// MARK: - Connection Mode

/**
 * Connection mode determines which side acts as the WebSocket server.
 * The puppeteer/puppet relationship stays the same regardless of mode.
 */
export type BridgeMode = 'local' | 'remote';

/**
 * Role in the puppeteer/puppet relationship (independent of connection direction)
 */
export type BridgeRole = 'puppeteer' | 'puppet';

// MARK: - JSON-RPC Messages

export interface BridgeRequest {
    jsonrpc: '2.0';
    id: string;
    method: string;
    params?: unknown;
}

export interface BridgeResponse {
    jsonrpc: '2.0';
    id: string;
    result?: unknown;
    error?: BridgeError;
}

export interface BridgeNotification {
    jsonrpc: '2.0';
    method: string;
    params?: unknown;
}

export interface BridgeError {
    code: number;
    message: string;
    data?: unknown;
}

// MARK: - Error Codes

export enum BridgeErrorCode {
    // Standard JSON-RPC
    ParseError = -32700,
    InvalidRequest = -32600,
    MethodNotFound = -32601,
    InvalidParams = -32602,
    InternalError = -32603,

    // Bridge-specific
    NotConnected = -1000,
    SessionExpired = -1001,
    ApprovalDenied = -2000,
    ApprovalTimeout = -2001,
    PathBlocked = -3000,
    CommandBlocked = -3001,
    FileNotFound = -4000,
    FileReadError = -4001,
    FileWriteError = -4002,
    TerminalError = -5000,
    Timeout = -6000,
}

// MARK: - Handshake

/**
 * Hello message sent by the connecting party during handshake.
 * In Local Mode: VS Code sends this to Axon
 * In Remote Mode: Axon sends this to VS Code
 */
export interface BridgeHello {
    // Mode and role information (new for Remote Mode support)
    mode?: BridgeMode;              // undefined defaults to 'local' for backward compatibility
    role?: BridgeRole;              // undefined inferred from mode

    // Workspace info (always present when VS Code sends, optional when Axon sends)
    workspaceId?: string;
    workspaceName?: string;
    workspaceRoot?: string;
    capabilities?: string[];
    extensionVersion?: string;
    vscodeVersion?: string;

    // Axon info (present when Axon sends in Remote Mode)
    axonVersion?: string;
    deviceName?: string;            // e.g., "Tom's iPhone"

    // Security
    pairingToken?: string;
}

/**
 * Welcome response sent by the server during handshake.
 * In Local Mode: Axon sends this to VS Code
 * In Remote Mode: VS Code sends this to Axon
 */
export interface BridgeWelcome {
    sessionId: string;
    mode?: BridgeMode;              // Echo back the mode for confirmation

    // Server info (always present)
    axonVersion?: string;           // Present in Local Mode (Axon is server)
    extensionVersion?: string;      // Present in Remote Mode (VS Code is server)

    // Workspace info (present in Remote Mode response from VS Code)
    workspaceId?: string;
    workspaceName?: string;
    workspaceRoot?: string;
    capabilities?: string[];

    supportedMethods: string[];
}

/**
 * Create a hello message from VS Code (Local Mode - existing behavior)
 */
export function createHelloFromVSCode(params: {
    workspaceId: string;
    workspaceName: string;
    workspaceRoot: string;
    capabilities: string[];
    extensionVersion: string;
    vscodeVersion: string;
    pairingToken?: string;
}): BridgeHello {
    return {
        mode: 'local',
        role: 'puppet',
        ...params,
    };
}

/**
 * Create a welcome response from VS Code (Remote Mode - new)
 */
export function createWelcomeFromVSCode(params: {
    sessionId: string;
    extensionVersion: string;
    workspaceId: string;
    workspaceName: string;
    workspaceRoot: string;
    capabilities: string[];
    supportedMethods: string[];
}): BridgeWelcome {
    return {
        mode: 'remote',
        ...params,
    };
}

/**
 * Get the effective mode (defaults to 'local' for backward compatibility)
 */
export function getEffectiveMode(hello: BridgeHello): BridgeMode {
    return hello.mode ?? 'local';
}

/**
 * Get the effective role (inferred from mode if not specified)
 */
export function getEffectiveRole(hello: BridgeHello): BridgeRole {
    if (hello.role) return hello.role;
    return getEffectiveMode(hello) === 'local' ? 'puppet' : 'puppeteer';
}

// MARK: - File Operations

export interface FileReadParams {
    path: string;
    encoding?: string;
    maxSize?: number;
}

export interface FileReadResult {
    content: string;
    size: number;
    encoding: string;
    path: string;
}

export interface FileWriteParams {
    path: string;
    content: string;
    createIfMissing?: boolean;
    encoding?: string;
}

export interface FileWriteResult {
    success: boolean;
    bytesWritten: number;
    created: boolean;
    path: string;
}

export interface FileListParams {
    path: string;
    recursive?: boolean;
    maxDepth?: number;
    includeHidden?: boolean;
}

export interface FileListResult {
    path: string;
    files: FileInfo[];
}

export interface FileInfo {
    name: string;
    path: string;
    type: 'file' | 'directory' | 'symlink' | 'unknown';
    size?: number;
    modified?: string;
}

// MARK: - Terminal Operations

export interface TerminalRunParams {
    command: string;
    args?: string[];
    cwd?: string;
    env?: Record<string, string>;
    timeout?: number;
}

export interface TerminalRunResult {
    output: string;
    stderr?: string;
    exitCode: number;
    duration: number;
    timedOut: boolean;
}

// MARK: - Workspace Operations

export interface WorkspaceInfoResult {
    name: string;
    rootPath: string;
    folders: WorkspaceFolder[];
    openFiles: string[];
}

export interface WorkspaceFolder {
    name: string;
    path: string;
}

// MARK: - Helper Types

export type BridgeMessage = BridgeRequest | BridgeResponse | BridgeNotification;

export function isRequest(msg: BridgeMessage): msg is BridgeRequest {
    return 'method' in msg && 'id' in msg;
}

export function isResponse(msg: BridgeMessage): msg is BridgeResponse {
    return ('result' in msg || 'error' in msg) && 'id' in msg && !('method' in msg);
}

export function isNotification(msg: BridgeMessage): msg is BridgeNotification {
    return 'method' in msg && !('id' in msg);
}

export function createRequest(method: string, params?: unknown): BridgeRequest {
    return {
        jsonrpc: '2.0',
        id: generateId(),
        method,
        params,
    };
}

export function createResponse(id: string, result?: unknown, error?: BridgeError): BridgeResponse {
    return {
        jsonrpc: '2.0',
        id,
        result,
        error,
    };
}

export function createNotification(method: string, params?: unknown): BridgeNotification {
    return {
        jsonrpc: '2.0',
        method,
        params,
    };
}

export function createError(code: BridgeErrorCode, message: string, data?: unknown): BridgeError {
    return { code, message, data };
}

function generateId(): string {
    return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}
