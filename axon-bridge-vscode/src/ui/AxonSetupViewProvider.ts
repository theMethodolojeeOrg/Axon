import * as vscode from "vscode";
import { BridgeClient } from "../BridgeClient";
import { BridgePairingInfo } from "../Protocol";

/**
 * AxonSetupViewProvider
 *
 * Read-only setup/status view that shows how to pair/connect to Axon.
 */
export class AxonSetupViewProvider implements vscode.WebviewViewProvider {
  public static readonly viewType = "axonSetupView";

  private view?: vscode.WebviewView;

  constructor(
    private readonly context: vscode.ExtensionContext,
    private readonly clientProvider: () => BridgeClient | undefined,
  ) {}

  resolveWebviewView(webviewView: vscode.WebviewView): void {
    this.view = webviewView;

    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [this.context.extensionUri],
    };

    webviewView.webview.onDidReceiveMessage(async (message) => {
      switch (message.type) {
        case "refresh":
          await this.render();
          break;

        case "copy":
          if (typeof message.text === "string") {
            await vscode.env.clipboard.writeText(message.text);
            vscode.window.showInformationMessage("Copied to clipboard");
          }
          break;
      }
    });

    void this.render();
  }

  reveal() {
    this.view?.show?.(true);
  }

  private async fetchPairingInfo(): Promise<
    { ok: true; info: BridgePairingInfo } | { ok: false; error: string }
  > {
    const client = this.clientProvider();
    if (!client || !client.isConnected()) {
      return {
        ok: false,
        error: "Not connected to Axon. Use “Axon: Connect to Bridge”.",
      };
    }

    try {
      const info = await client.getPairingInfo();
      return { ok: true, info };
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) };
    }
  }

  private async render() {
    if (!this.view) return;

    const state = await this.fetchPairingInfo();

    this.view.webview.html = this.getHtml(
      state.ok ? state.info : undefined,
      state.ok ? undefined : state.error,
    );
  }

  private getHtml(info?: BridgePairingInfo, error?: string) {
    const nonce = getNonce();

    const body = error
      ? `<div class="card error">
                    <h3>Axon Setup</h3>
                    <p>${escapeHtml(error)}</p>
                    <button class="primary" id="refresh">Refresh</button>
               </div>`
      : `<div class="card">
                    <div class="row">
                        <h3>Axon Setup</h3>
                        <button class="primary" id="refresh">Refresh</button>
                    </div>

                    <div class="kv">
                        <div class="k">Device</div>
                        <div class="v">${escapeHtml(info?.deviceName ?? "Unknown")}</div>

                        <div class="k">Bridge URL (localhost)</div>
                        <div class="v mono">
                            ${escapeHtml(info?.axonBridgeWsLocalhostUrl ?? "")}
                            <button class="small" data-copy="${escapeHtmlAttr(info?.axonBridgeWsLocalhostUrl ?? "")}">Copy</button>
                        </div>

                        <div class="k">Port</div>
                        <div class="v mono">${escapeHtml(String(info?.axonBridgePort ?? ""))}</div>

                        <div class="k">Pairing token required</div>
                        <div class="v">${info?.requiredPairingToken ? "Yes" : "No"}</div>

                        <div class="k">Active VS Code connections</div>
                        <div class="v">${escapeHtml(String(info?.connectionCount ?? 0))}</div>

                        <div class="k">QR payload</div>
                        <div class="v mono">
                            ${escapeHtml(info?.qrPayload ?? "")}
                            <button class="small" data-copy="${escapeHtmlAttr(info?.qrPayload ?? "")}">Copy</button>
                        </div>
                    </div>

                    <p class="hint">Note: Axon’s WebSocket bridge listens on localhost by design. The QR payload is intended for future phone-side pairing UX.</p>
               </div>`;

    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';" />
    <title>Axon Setup</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; padding: 12px; color: var(--vscode-foreground); }
        .card { border: 1px solid var(--vscode-editorWidget-border); border-radius: 10px; padding: 12px; background: var(--vscode-editorWidget-background); }
        .error { border-color: var(--vscode-inputValidation-errorBorder); }
        .row { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
        .kv { display: grid; grid-template-columns: 160px 1fr; gap: 10px 12px; margin-top: 12px; }
        .k { opacity: 0.8; }
        .v { word-break: break-word; }
        .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace; }
        button { cursor: pointer; }
        button.primary { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: 0; border-radius: 6px; padding: 6px 10px; }
        button.small { margin-left: 8px; font-size: 12px; border-radius: 6px; padding: 2px 8px; background: transparent; color: var(--vscode-textLink-foreground); border: 1px solid var(--vscode-textLink-foreground); }
        .hint { margin-top: 12px; font-size: 12px; opacity: 0.75; }
    </style>
</head>
<body>
    ${body}

    <script nonce="${nonce}">
        const vscode = acquireVsCodeApi();

        document.getElementById('refresh')?.addEventListener('click', () => {
            vscode.postMessage({ type: 'refresh' });
        });

        document.querySelectorAll('[data-copy]').forEach(btn => {
            btn.addEventListener('click', () => {
                vscode.postMessage({ type: 'copy', text: btn.getAttribute('data-copy') });
            });
        });
    </script>
</body>
</html>`;
  }
}

function getNonce() {
  let text = "";
  const possible =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  for (let i = 0; i < 32; i++) {
    text += possible.charAt(Math.floor(Math.random() * possible.length));
  }
  return text;
}

function escapeHtml(str: string) {
  return str
    .replace(/&/g, "&")
    .replace(/</g, "<")
    .replace(/>/g, ">")
    .replace(/"/g, '"')
    .replace(/'/g, "&#039;");
}

function escapeHtmlAttr(str: string) {
  // attribute-safe (same as html for our usage)
  return escapeHtml(str);
}
