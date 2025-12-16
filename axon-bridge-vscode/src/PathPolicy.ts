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
