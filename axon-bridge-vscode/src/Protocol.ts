/**
 * Protocol.ts
 *
 * JSON-RPC 2.0 style protocol definitions for Axon Bridge communication.
 * These types mirror the Swift BridgeProtocol.swift definitions.
 */

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

export interface BridgeHello {
    workspaceId: string;
    workspaceName: string;
    workspaceRoot: string;
    capabilities: string[];
    extensionVersion: string;
    vscodeVersion: string;
}

export interface BridgeWelcome {
    sessionId: string;
    axonVersion: string;
    supportedMethods: string[];
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
