/**
 * FileHandler.ts
 *
 * Handles file operations requested by Axon:
 * - file/read: Read file contents
 * - file/write: Write or create files
 * - file/list: List directory contents
 */

import * as vscode from 'vscode';
import * as path from 'path';
import {
    FileReadParams,
    FileReadResult,
    FileWriteParams,
    FileWriteResult,
    FileListParams,
    FileListResult,
    FileInfo,
    BridgeError,
    BridgeErrorCode,
    createError,
} from '../Protocol';
import { PathPolicy } from '../PathPolicy';

export class FileHandler {
    constructor() {}

    /**
     * Resolve and validate a path using the workspace sandbox policy.
     */
    private resolvePath(filePath: string): vscode.Uri {
        return PathPolicy.resolveAndValidatePath(filePath, { purpose: 'file path' });
    }

    /**
     * Read file contents
     */
    async read(params: FileReadParams): Promise<FileReadResult> {
        const uri = this.resolvePath(params.path);
        const encoding = params.encoding ?? 'utf-8';
        const maxSize = params.maxSize ?? 10 * 1024 * 1024; // 10MB default

        try {
            // Check file exists
            const stat = await vscode.workspace.fs.stat(uri);

            if (stat.size > maxSize) {
                throw createError(
                    BridgeErrorCode.FileReadError,
                    `File too large: ${stat.size} bytes (max: ${maxSize})`
                );
            }

            // Read file
            const content = await vscode.workspace.fs.readFile(uri);
            const textContent = new TextDecoder(encoding).decode(content);

            return {
                content: textContent,
                size: stat.size,
                encoding,
                path: uri.fsPath,
            };
        } catch (error) {
            if (error instanceof vscode.FileSystemError) {
                if (error.code === 'FileNotFound') {
                    throw createError(BridgeErrorCode.FileNotFound, `File not found: ${params.path}`);
                }
            }
            throw createError(
                BridgeErrorCode.FileReadError,
                `Failed to read file: ${error instanceof Error ? error.message : String(error)}`
            );
        }
    }

    /**
     * Write file contents
     */
    async write(params: FileWriteParams): Promise<FileWriteResult> {
        const uri = this.resolvePath(params.path);
        const encoding = params.encoding ?? 'utf-8';
        const createIfMissing = params.createIfMissing ?? true;

        try {
            // Check if file exists
            let created = false;
            try {
                await vscode.workspace.fs.stat(uri);
            } catch {
                if (!createIfMissing) {
                    throw createError(BridgeErrorCode.FileNotFound, `File not found: ${params.path}`);
                }
                created = true;

                // Ensure parent directory exists
                const parentUri = vscode.Uri.file(path.dirname(uri.fsPath));
                try {
                    await vscode.workspace.fs.createDirectory(parentUri);
                } catch {
                    // Directory might already exist, ignore
                }
            }

            // Encode and write
            const encoded = new TextEncoder().encode(params.content);
            await vscode.workspace.fs.writeFile(uri, encoded);

            return {
                success: true,
                bytesWritten: encoded.length,
                created,
                path: uri.fsPath,
            };
        } catch (error) {
            if ((error as BridgeError).code) {
                throw error;
            }
            throw createError(
                BridgeErrorCode.FileWriteError,
                `Failed to write file: ${error instanceof Error ? error.message : String(error)}`
            );
        }
    }

    /**
     * List directory contents
     */
    async list(params: FileListParams): Promise<FileListResult> {
        const uri = this.resolvePath(params.path);
        const includeHidden = params.includeHidden ?? false;

        try {
            const entries = await vscode.workspace.fs.readDirectory(uri);

            const files: FileInfo[] = [];

            for (const [name, type] of entries) {
                // Skip hidden files if not requested
                if (!includeHidden && name.startsWith('.')) {
                    continue;
                }

                const entryUri = vscode.Uri.joinPath(uri, name);
                let fileInfo: FileInfo = {
                    name,
                    path: entryUri.fsPath,
                    type: this.mapFileType(type),
                };

                // Get size for files
                if (type === vscode.FileType.File) {
                    try {
                        const stat = await vscode.workspace.fs.stat(entryUri);
                        fileInfo.size = stat.size;
                        fileInfo.modified = new Date(stat.mtime).toISOString();
                    } catch {
                        // Ignore stat errors
                    }
                }

                files.push(fileInfo);
            }

            // Sort: directories first, then alphabetically
            files.sort((a, b) => {
                if (a.type === 'directory' && b.type !== 'directory') return -1;
                if (a.type !== 'directory' && b.type === 'directory') return 1;
                return a.name.localeCompare(b.name);
            });

            return {
                path: uri.fsPath,
                files,
            };
        } catch (error) {
            if (error instanceof vscode.FileSystemError) {
                if (error.code === 'FileNotFound') {
                    throw createError(BridgeErrorCode.FileNotFound, `Directory not found: ${params.path}`);
                }
            }
            throw createError(
                BridgeErrorCode.FileReadError,
                `Failed to list directory: ${error instanceof Error ? error.message : String(error)}`
            );
        }
    }

    private mapFileType(type: vscode.FileType): FileInfo['type'] {
        switch (type) {
            case vscode.FileType.File:
                return 'file';
            case vscode.FileType.Directory:
                return 'directory';
            case vscode.FileType.SymbolicLink:
                return 'symlink';
            default:
                return 'unknown';
        }
    }
}
