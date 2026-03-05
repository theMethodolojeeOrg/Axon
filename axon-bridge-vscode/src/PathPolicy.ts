/**
 * PathPolicy.ts
 *
 * Defense-in-depth policy for the Axon Bridge VS Code extension.
 *
 * The VS Code bridge is intentionally sandboxed to the current workspace.
 * - File operations may only access paths under an allowed workspace folder.
 * - Terminal working directory (cwd) must also be under an allowed workspace folder.
 */

import * as vscode from 'vscode';
import * as path from 'path';
import { BridgeErrorCode, createError } from './Protocol';

export type AllowedRoot = {
    name: string;
    fsPath: string; // absolute normalized
};

export class PathPolicy {
    /**
     * Returns normalized absolute workspace roots.
     * Supports multi-root workspaces.
     */
    static getAllowedRoots(): AllowedRoot[] {
        const folders = vscode.workspace.workspaceFolders ?? [];
        return folders.map(f => ({
            name: f.name,
            fsPath: path.resolve(f.uri.fsPath),
        }));
    }

    /**
     * Resolve a user-provided path into an absolute path, then enforce it is inside
     * one of the allowed workspace roots.
     */
    static resolveAndValidatePath(inputPath: string, opts?: { purpose?: string }): vscode.Uri {
        const purpose = opts?.purpose ?? 'path';

        const allowedRoots = this.getAllowedRoots();
        if (allowedRoots.length === 0) {
            throw createError(
                BridgeErrorCode.PathBlocked,
                `No workspace is open; refusing to access ${purpose}.`
            );
        }

        const trimmed = inputPath.trim();
        if (!trimmed) {
            throw createError(BridgeErrorCode.InvalidParams, `Missing ${purpose}.`);
        }

        // Default relative paths to first workspace folder.
        const base = allowedRoots[0].fsPath;

        const resolved = path.resolve(path.isAbsolute(trimmed) ? trimmed : path.join(base, trimmed));

        const matchingRoot = allowedRoots.find(r => this.isDescendantPath(resolved, r.fsPath));
        if (!matchingRoot) {
            const rootsList = allowedRoots.map(r => `- ${r.name}: ${r.fsPath}`).join('\n');
            throw createError(
                BridgeErrorCode.PathBlocked,
                `Refusing to access ${purpose} outside the workspace.\n\nRequested: ${resolved}\n\nAllowed workspace roots:\n${rootsList}`
            );
        }

        return vscode.Uri.file(resolved);
    }

    /**
     * Resolve a cwd parameter (optional). If not provided, returns the first workspace root.
     */
    static resolveAndValidateCwd(cwd: string | undefined | null): string {
        const allowedRoots = this.getAllowedRoots();
        if (allowedRoots.length === 0) {
            throw createError(
                BridgeErrorCode.PathBlocked,
                'No workspace is open; refusing to run terminal commands.'
            );
        }

        if (!cwd || !cwd.trim()) {
            return allowedRoots[0].fsPath;
        }

        const resolved = path.resolve(path.isAbsolute(cwd) ? cwd : path.join(allowedRoots[0].fsPath, cwd));

        const matchingRoot = allowedRoots.find(r => this.isDescendantPath(resolved, r.fsPath));
        if (!matchingRoot) {
            const rootsList = allowedRoots.map(r => `- ${r.name}: ${r.fsPath}`).join('\n');
            throw createError(
                BridgeErrorCode.PathBlocked,
                `Refusing to run terminal command with cwd outside the workspace.\n\nRequested cwd: ${resolved}\n\nAllowed workspace roots:\n${rootsList}`
            );
        }

        return resolved;
    }

    /**
     * Check if a file path matches any of the configured blocked patterns.
     * Patterns are glob-style from the axonBridge.blockedPatterns setting.
     */
    static isPathBlocked(filePath: string): boolean {
        const config = vscode.workspace.getConfiguration('axonBridge');
        const patterns = config.get<string[]>('blockedPatterns', []);

        for (const pattern of patterns) {
            if (this.matchesGlobPattern(filePath, pattern)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Get the configured max file size in bytes.
     */
    static getMaxFileSize(): number {
        const config = vscode.workspace.getConfiguration('axonBridge');
        return config.get<number>('maxFileSize', 10 * 1024 * 1024);
    }

    /**
     * Simple glob pattern matching (supports ** and *).
     */
    private static matchesGlobPattern(filePath: string, pattern: string): boolean {
        // Convert glob to regex
        let regex = '^';
        let i = 0;
        while (i < pattern.length) {
            const char = pattern[i];
            if (char === '*') {
                if (i + 1 < pattern.length && pattern[i + 1] === '*') {
                    regex += '.*';
                    i += 2;
                    if (i < pattern.length && pattern[i] === '/') {
                        i++;
                    }
                    continue;
                } else {
                    regex += '[^/]*';
                }
            } else if (char === '?') {
                regex += '[^/]';
            } else if (char === '.') {
                regex += '\\.';
            } else {
                regex += char;
            }
            i++;
        }
        regex += '$';

        try {
            return new RegExp(regex).test(filePath);
        } catch {
            return false;
        }
    }

    /**
     * Returns true if candidate is the same as root, or inside root.
     * Uses path.relative to avoid naive prefix checks.
     */
    private static isDescendantPath(candidate: string, root: string): boolean {
        const rel = path.relative(root, candidate);
        // rel === '' means same path.
        // rel starts with '..' means outside.
        // rel includes '..' segments at start also means outside.
        return rel === '' || (!rel.startsWith('..' + path.sep) && rel !== '..' && !path.isAbsolute(rel));
    }
}
