/**
 * WorkspaceHandler.ts
 *
 * Handles workspace operations requested by Axon:
 * - workspace/info: Get workspace metadata
 */

import * as vscode from 'vscode';
import {
    WorkspaceInfoResult,
    WorkspaceFolder,
} from '../Protocol';

export class WorkspaceHandler {
    /**
     * Get workspace information
     */
    async getInfo(): Promise<WorkspaceInfoResult> {
        const folders = vscode.workspace.workspaceFolders ?? [];

        // Get workspace name
        const name = vscode.workspace.name ?? folders[0]?.name ?? 'Untitled';

        // Get root path
        const rootPath = folders[0]?.uri.fsPath ?? '';

        // Map workspace folders
        const workspaceFolders: WorkspaceFolder[] = folders.map(folder => ({
            name: folder.name,
            path: folder.uri.fsPath,
        }));

        // Get open files
        const openFiles = vscode.window.visibleTextEditors
            .map(editor => editor.document.uri.fsPath)
            .filter(path => path.startsWith(rootPath));

        return {
            name,
            rootPath,
            folders: workspaceFolders,
            openFiles,
        };
    }
}
