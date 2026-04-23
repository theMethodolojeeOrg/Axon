/**
 * TerminalHandler.ts
 *
 * Handles terminal command execution requested by Axon:
 * - terminal/run: Execute a command and capture output
 */

import * as vscode from 'vscode';
import { execFile } from 'child_process';
import * as os from 'os';
import * as crypto from 'crypto';
import * as pty from 'node-pty';
import {
    TerminalRunParams,
    TerminalRunResult,
    TerminalSessionCloseParams,
    TerminalSessionExitedNotification,
    TerminalSessionInputParams,
    TerminalSessionOutputNotification,
    TerminalSessionResizeParams,
    TerminalSessionStartParams,
    TerminalSessionStartResult,
    BridgeErrorCode,
    createError,
} from '../Protocol';
import { PathPolicy } from '../PathPolicy';

type TerminalNotificationSender = (method: string, params: unknown) => void;

export class TerminalHandler {
    private sessions = new Map<string, pty.IPty>();

    constructor(private readonly sendNotification?: TerminalNotificationSender) {}

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

    startSession(params: TerminalSessionStartParams): TerminalSessionStartResult {
        const cwd = PathPolicy.resolveAndValidateCwd(params.cwd);
        const shell = params.shell?.trim() || process.env.SHELL || (os.platform() === 'win32' ? 'powershell.exe' : '/bin/zsh');
        const cols = Math.max(20, params.cols || 100);
        const rows = Math.max(5, params.rows || 30);
        const sessionId = crypto.randomUUID();

        const terminal = pty.spawn(shell, ['-l'], {
            name: 'xterm-256color',
            cols,
            rows,
            cwd,
            env: {
                ...process.env,
                TERM: 'xterm-256color',
            },
        });

        terminal.onData((data) => {
            const payload: TerminalSessionOutputNotification = { sessionId, data };
            this.sendNotification?.('terminal/output', payload);
        });

        terminal.onExit(({ exitCode }) => {
            this.sessions.delete(sessionId);
            const payload: TerminalSessionExitedNotification = { sessionId, exitCode };
            this.sendNotification?.('terminal/exited', payload);
        });

        this.sessions.set(sessionId, terminal);
        return { sessionId, cwd, shell };
    }

    input(params: TerminalSessionInputParams): { ok: true } {
        const terminal = this.sessions.get(params.sessionId);
        if (!terminal) {
            throw createError(BridgeErrorCode.InvalidParams, `Unknown terminal session: ${params.sessionId}`);
        }
        terminal.write(params.data);
        return { ok: true };
    }

    resize(params: TerminalSessionResizeParams): { ok: true } {
        const terminal = this.sessions.get(params.sessionId);
        if (!terminal) {
            throw createError(BridgeErrorCode.InvalidParams, `Unknown terminal session: ${params.sessionId}`);
        }
        terminal.resize(Math.max(20, params.cols), Math.max(5, params.rows));
        return { ok: true };
    }

    close(params: TerminalSessionCloseParams): { ok: true } {
        const terminal = this.sessions.get(params.sessionId);
        if (terminal) {
            terminal.kill();
            this.sessions.delete(params.sessionId);
        }
        return { ok: true };
    }

    dispose() {
        for (const terminal of this.sessions.values()) {
            terminal.kill();
        }
        this.sessions.clear();
    }
}
