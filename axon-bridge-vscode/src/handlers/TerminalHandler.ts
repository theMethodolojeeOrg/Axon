/**
 * TerminalHandler.ts
 *
 * Handles terminal command execution requested by Axon:
 * - terminal/run: Execute a command and capture output
 */

import * as vscode from 'vscode';
import { execFile } from 'child_process';
import {
    TerminalRunParams,
    TerminalRunResult,
    BridgeErrorCode,
    createError,
} from '../Protocol';
import { PathPolicy } from '../PathPolicy';

export class TerminalHandler {
    constructor() {}

    /**
     * Run a terminal command and capture output
     */
    async run(params: TerminalRunParams): Promise<TerminalRunResult> {
        const command = params.command;
        const args = params.args ?? [];
        const timeout = params.timeout ?? 60000; // 60s default

        // Resolve working directory (sandboxed to workspace)
        const cwd = PathPolicy.resolveAndValidateCwd(params.cwd);

        // Basic command validation
        if (!command.trim()) {
            throw createError(BridgeErrorCode.InvalidParams, 'Command cannot be empty');
        }

        const startTime = Date.now();

        const maxBuffer = 10 * 1024 * 1024; // 10MB output buffer

        return new Promise((resolve) => {
            const childProcess = execFile(
                command,
                args,
                {
                    cwd,
                    timeout,
                    maxBuffer,
                    windowsHide: true,
                    shell: false,
                    env: {
                        ...process.env,
                        ...params.env,
                    },
                },
                (error, stdout, stderr) => {
                    const duration = Date.now() - startTime;

                    const anyError = error as any;
                    const timedOut = anyError?.killed === true || anyError?.signal === 'SIGTERM';

                    resolve({
                        output: stdout ?? '',
                        stderr: stderr ?? undefined,
                        exitCode: typeof anyError?.code === 'number' ? anyError.code : (timedOut ? 124 : 0),
                        duration,
                        timedOut,
                    });
                }
            );

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
