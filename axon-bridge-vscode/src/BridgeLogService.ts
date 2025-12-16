/**
 * BridgeLogService.ts
 *
 * VS Code-side mirror of Axon's BridgeLogService.
 * Captures incoming/outgoing WebSocket JSON-RPC traffic, validates structure,
 * pretty-prints, retains a bounded buffer, and mirrors output to an OutputChannel.
 */

import * as vscode from 'vscode';

export type BridgeLogDirection = 'incoming' | 'outgoing';
export type BridgeLogMessageType = 'request' | 'response' | 'notification' | 'error' | 'unknown';

export interface BridgeLogEntry {
    id: string;
    timestamp: number; // epoch ms
    direction: BridgeLogDirection;
    messageType: BridgeLogMessageType;
    method?: string;
    requestId?: string;
    rawJSON: string;
    prettyJSON: string;
    isValid: boolean;
    validationErrors: string[];
}

export interface BridgeLogFilter {
    filterText: string;
    showIncoming: boolean;
    showOutgoing: boolean;
    showRequests: boolean;
    showResponses: boolean;
    showNotifications: boolean;
    showErrors: boolean;
    onlyShowInvalid: boolean;
}

const DEFAULT_FILTER: BridgeLogFilter = {
    filterText: '',
    showIncoming: true,
    showOutgoing: true,
    showRequests: true,
    showResponses: true,
    showNotifications: true,
    showErrors: true,
    onlyShowInvalid: false,
};

export class BridgeLogService {
    private static _shared: BridgeLogService | undefined;

    static get shared(): BridgeLogService {
        if (!this._shared) {
            this._shared = new BridgeLogService();
        }
        return this._shared;
    }

    private entries: BridgeLogEntry[] = [];
    private maxEntries = 500;

    private output: vscode.OutputChannel;

    private constructor() {
        this.output = vscode.window.createOutputChannel('Axon Bridge');
    }

    showOutput() {
        this.output.show(true);
    }

    clear() {
        this.entries = [];
        this.output.clear();
    }

    getEntries(): BridgeLogEntry[] {
        return this.entries;
    }

    getFilteredEntries(filter: BridgeLogFilter = DEFAULT_FILTER): BridgeLogEntry[] {
        const text = filter.filterText.trim().toLowerCase();

        return this.entries.filter(e => {
            if (e.direction === 'incoming' && !filter.showIncoming) return false;
            if (e.direction === 'outgoing' && !filter.showOutgoing) return false;

            switch (e.messageType) {
                case 'request':
                    if (!filter.showRequests) return false;
                    break;
                case 'response':
                    if (!filter.showResponses) return false;
                    break;
                case 'notification':
                    if (!filter.showNotifications) return false;
                    break;
                case 'error':
                    if (!filter.showErrors) return false;
                    break;
                case 'unknown':
                    break;
            }

            if (filter.onlyShowInvalid && e.isValid) return false;

            if (text) {
                const matchesMethod = (e.method ?? '').toLowerCase().includes(text);
                const matchesId = (e.requestId ?? '').toLowerCase().includes(text);
                const matchesJson = e.rawJSON.toLowerCase().includes(text);
                if (!matchesMethod && !matchesId && !matchesJson) return false;
            }

            return true;
        });
    }

    export(): string {
        return JSON.stringify(this.entries, null, 2);
    }

    logIncoming(raw: string) {
        this.addEntry(this.createEntry('incoming', raw));
    }

    logOutgoing(raw: string) {
        this.addEntry(this.createEntry('outgoing', raw));
    }

    private addEntry(entry: BridgeLogEntry) {
        // Newest first
        this.entries.unshift(entry);
        if (this.entries.length > this.maxEntries) {
            this.entries = this.entries.slice(0, this.maxEntries);
        }

        // Mirror to OutputChannel
        this.output.appendLine(this.formatForOutput(entry));
    }

    private formatForOutput(entry: BridgeLogEntry): string {
        const ts = new Date(entry.timestamp);
        const time = ts.toISOString().split('T')[1]?.replace('Z', '') ?? ts.toISOString();

        const dir = entry.direction === 'outgoing' ? '→' : '←';
        const type = entry.messageType.toUpperCase();
        const summary = entry.method
            ? entry.method
            : entry.messageType === 'response'
                ? `response ${entry.requestId ?? ''}`
                : entry.messageType;

        const validity = entry.isValid ? '' : ` INVALID(${entry.validationErrors.join('; ')})`;

        return `[${time}] ${dir} ${type} ${summary}${validity}\n${entry.prettyJSON}\n`;
    }

    private createEntry(direction: BridgeLogDirection, raw: string): BridgeLogEntry {
        const timestamp = Date.now();
        const id = `${timestamp}-${Math.random().toString(16).slice(2)}`;

        let messageType: BridgeLogMessageType = 'unknown';
        let method: string | undefined;
        let requestId: string | undefined;

        let prettyJSON = raw;
        let isValid = true;
        let validationErrors: string[] = [];

        try {
            const obj = JSON.parse(raw) as any;

            method = typeof obj.method === 'string' ? obj.method : undefined;
            requestId = obj.id !== undefined ? String(obj.id) : undefined;

            if (obj.error !== undefined) {
                messageType = 'error';
            } else if (obj.result !== undefined) {
                messageType = 'response';
            } else if (obj.method !== undefined) {
                messageType = obj.id !== undefined ? 'request' : 'notification';
            }

            try {
                prettyJSON = JSON.stringify(obj, Object.keys(obj).sort(), 2);
            } catch {
                // ignore
            }

            validationErrors = this.validateJSONRPC(obj);
            if (validationErrors.length > 0) {
                isValid = false;
            }
        } catch (e) {
            isValid = false;
            validationErrors = ['Invalid JSON: Unable to parse'];
        }

        return {
            id,
            timestamp,
            direction,
            messageType,
            method,
            requestId,
            rawJSON: raw,
            prettyJSON,
            isValid,
            validationErrors,
        };
    }

    private validateJSONRPC(obj: any): string[] {
        const errors: string[] = [];

        if (obj?.jsonrpc !== '2.0') {
            if (obj?.jsonrpc === undefined) {
                errors.push('Missing required field: jsonrpc');
            } else {
                errors.push(`jsonrpc field should be "2.0", got "${String(obj.jsonrpc)}"`);
            }
        }

        const hasMethod = obj?.method !== undefined;
        const hasResult = obj?.result !== undefined;
        const hasError = obj?.error !== undefined;

        if (hasResult || hasError) {
            if (obj?.id === undefined) {
                errors.push('Response missing required field: id');
            }
            if (hasResult && hasError) {
                errors.push('Response cannot have both result and error');
            }
        } else if (hasMethod) {
            if (typeof obj.method !== 'string') {
                errors.push('Method must be a string');
            } else if (!obj.method) {
                errors.push('Method cannot be empty');
            }
        } else {
            errors.push('Message must have method (request/notification) or result/error (response)');
        }

        if (obj?.error !== undefined) {
            if (typeof obj.error !== 'object' || obj.error === null) {
                errors.push('Error must be an object');
            } else {
                if (obj.error.code === undefined) errors.push('Error missing required field: code');
                else if (!Number.isInteger(obj.error.code)) errors.push('Error code must be an integer');

                if (obj.error.message === undefined) errors.push('Error missing required field: message');
                else if (typeof obj.error.message !== 'string') errors.push('Error message must be a string');
            }
        }

        return errors;
    }
}
