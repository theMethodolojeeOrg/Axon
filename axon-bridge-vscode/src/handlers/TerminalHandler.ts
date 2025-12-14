/**
 * TerminalHandler.ts
 *
 * Handles terminal command execution requested by Axon:
 * - terminal/run: Execute a command and capture output
 */

import * as vscode from 'vscode';
import { exec, ExecOptions } from 'child_process';
import * as path from 'path';
import {
    TerminalRunParams,
    TerminalRunResult,
    BridgeErrorCode,
    createError,
} from '../Protocol';

export class TerminalHandler {
    private workspaceRoot: string;

    constructor() {
        const folders = vscode.workspace.workspaceFolders;
        this.workspaceRoot = folders?.[0]?.uri.fsPath ?? process.cwd();
    }

    /**
     * Run a terminal command and capture output
     */
    async run(params: TerminalRunParams): Promise<TerminalRunResult> {
        const command = params.command;
        const args = params.args ?? [];
        const timeout = params.timeout ?? 60000; // 60s default

        // Build full command
        const fullCommand = args.length > 0
            ? `${command} ${args.map(a => `"${a}"`).join(' ')}`
            : command;

        // Resolve working directory
        let cwd = this.workspaceRoot;
        if (params.cwd) {
            cwd = path.isAbsolute(params.cwd)
                ? params.cwd
                : path.join(this.workspaceRoot, params.cwd);
        }

        const startTime = Date.now();

        const options: ExecOptions = {
            cwd,
            timeout,
            maxBuffer: 10 * 1024 * 1024, // 10MB output buffer
            env: {
                ...process.env,
                ...params.env,
            },
        };

        return new Promise((resolve) => {
            const childProcess = exec(fullCommand, options, (error, stdout, stderr) => {
                const duration = Date.now() - startTime;

                // Check if timed out
                const timedOut = error?.killed === true || error?.code === null;

                resolve({
                    output: typeof stdout === 'string' ? stdout : stdout.toString(),
                    stderr: stderr ? (typeof stderr === 'string' ? stderr : stderr.toString()) : undefined,
                    exitCode: error?.code ?? 0,
                    duration,
                    timedOut,
                });
            });

            // Handle process errors
            childProcess.on('error', (error) => {
                const duration = Date.now() - startTime;
                resolve({
                    output: '',
                    stderr: error.message,
                    exitCode: 1,
                    duration,
                    timedOut: false,
                });
            });
        });
    }
}
