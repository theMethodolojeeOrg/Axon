import * as vscode from "vscode";
import { BridgeClient } from "../BridgeClient";
import {
  ChatConversationSummary,
  ChatListConversationsResult,
  ChatGetMessagesResult,
} from "../Protocol";

/**
 * AxonChatViewProvider
 *
 * Read-only chat mirroring: list conversations + view messages.
 */
export class AxonChatViewProvider implements vscode.WebviewViewProvider {
  public static readonly viewType = "axonChatView";

  private view?: vscode.WebviewView;
  private selectedConversationId?: string;

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

        case "selectConversation":
          if (typeof message.conversationId === "string") {
            this.selectedConversationId = message.conversationId;
            await this.render();
          }
          break;
      }
    });

    void this.render();
  }

  reveal() {
    this.view?.show?.(true);
  }

  private getClientOrError(): { client: BridgeClient } | { error: string } {
    const client = this.clientProvider();
    if (!client || !client.isConnected()) {
      return { error: "Not connected to Axon. Use ‘Axon: Connect to Bridge’." };
    }
    return { client };
  }

  private async fetchData(): Promise<
    | {
        ok: true;
        conversations: ChatConversationSummary[];
        messages?: ChatGetMessagesResult;
      }
    | { ok: false; error: string }
  > {
    const res = this.getClientOrError();
    if ("error" in res) return { ok: false, error: res.error };

    try {
      const list =
        (await res.client.chatListConversations()) as ChatListConversationsResult;
      const conversations = list.conversations ?? [];

      const selected = this.selectedConversationId ?? conversations[0]?.id;
      this.selectedConversationId = selected;

      if (!selected) {
        return { ok: true, conversations, messages: undefined };
      }

      const messages = await res.client.chatGetMessages({
        conversationId: selected,
        limit: 200,
      });
      return { ok: true, conversations, messages };
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) };
    }
  }

  private async render() {
    if (!this.view) return;

    const state = await this.fetchData();
    this.view.webview.html = this.getHtml(state);
  }

  private getHtml(
    state:
      | {
          ok: true;
          conversations: ChatConversationSummary[];
          messages?: ChatGetMessagesResult;
        }
      | { ok: false; error: string },
  ) {
    const nonce = getNonce();

    if (!state.ok) {
      return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';" />
<title>Axon Chat</title>
<style>
  :root { --space: 12px; --radius: 12px; }
  body {
    margin: 0;
    padding: var(--space);
    color: var(--vscode-foreground);
    background: linear-gradient(150deg, color-mix(in srgb, var(--vscode-sideBar-background) 90%, transparent), var(--vscode-editor-background));
    font-family: "Avenir Next", "Segoe UI", "Helvetica Neue", sans-serif;
  }
  .card {
    border: 1px solid var(--vscode-editorWidget-border);
    border-radius: var(--radius);
    background: color-mix(in srgb, var(--vscode-editorWidget-background) 92%, transparent);
    padding: var(--space);
    display: grid;
    gap: 10px;
  }
  .btn {
    border-radius: 10px;
    border: 1px solid transparent;
    background: var(--vscode-button-background);
    color: var(--vscode-button-foreground);
    padding: 7px 10px;
    cursor: pointer;
    justify-self: start;
  }
</style>
</head>
<body>
<div class="card">
  <h3>Axon Chat</h3>
  <p>${escapeHtml(state.error)}</p>
  <button class="btn" id="refresh">Refresh</button>
</div>
<script nonce="${nonce}">
const vscode = acquireVsCodeApi();
document.getElementById('refresh')?.addEventListener('click', () => vscode.postMessage({ type: 'refresh' }));
</script>
</body>
</html>`;
    }

    const conversationsHtml = state.conversations
      .map((c) => {
        const isSelected = c.id === this.selectedConversationId;
        const title = c.title?.trim() ? c.title : c.id;
        return `<button class="conv ${isSelected ? "selected" : ""}" data-conv="${escapeHtmlAttr(
          c.id,
        )}">
  <div class="title">${escapeHtml(title)}</div>
  <div class="meta">${escapeHtml(c.updatedAt ?? "")}</div>
</button>`;
      })
      .join("");

    const messagesHtml = (state.messages?.messages ?? [])
      .map((m) => {
        return `<article class="msg">
  <header class="hdr">
    <span class="role">${escapeHtml(m.role)}</span>
    <span class="time">${escapeHtml(m.createdAt ?? "")}</span>
  </header>
  <pre class="content">${escapeHtml(m.content ?? "")}</pre>
</article>`;
      })
      .join("");

    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';" />
<title>Axon Chat</title>
<style>
  :root {
    --space-1: 6px;
    --space-2: 10px;
    --space-3: 14px;
    --radius-1: 10px;
    --radius-2: 14px;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    color: var(--vscode-foreground);
    background: linear-gradient(152deg, color-mix(in srgb, var(--vscode-sideBar-background) 90%, transparent), var(--vscode-editor-background));
    font-family: "Avenir Next", "Segoe UI", "Helvetica Neue", sans-serif;
  }
  .header {
    padding: var(--space-2) var(--space-3);
    border-bottom: 1px solid var(--vscode-editorWidget-border);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-2);
    background: color-mix(in srgb, var(--vscode-sideBar-background) 90%, transparent);
    position: sticky;
    top: 0;
    z-index: 1;
  }
  .header strong { font-size: 13px; letter-spacing: 0.3px; }
  .btn {
    border-radius: var(--radius-1);
    border: 1px solid transparent;
    background: var(--vscode-button-background);
    color: var(--vscode-button-foreground);
    padding: 7px 10px;
    cursor: pointer;
    font-size: 12px;
  }
  .container {
    display: grid;
    grid-template-columns: minmax(170px, 230px) minmax(0, 1fr);
    min-height: calc(100vh - 48px);
  }
  .left {
    border-right: 1px solid var(--vscode-editorWidget-border);
    overflow: auto;
    background: color-mix(in srgb, var(--vscode-sideBar-background) 86%, transparent);
  }
  .right {
    overflow: auto;
    padding: var(--space-3);
    display: grid;
    align-content: start;
    gap: var(--space-2);
  }
  .conv {
    width: 100%;
    text-align: left;
    border: 0;
    border-bottom: 1px solid color-mix(in srgb, var(--vscode-editorWidget-border) 70%, transparent);
    background: transparent;
    color: var(--vscode-foreground);
    padding: var(--space-2) var(--space-3);
    cursor: pointer;
    display: grid;
    gap: 2px;
  }
  .conv:hover { background: color-mix(in srgb, var(--vscode-list-hoverBackground) 70%, transparent); }
  .conv.selected { background: color-mix(in srgb, var(--vscode-list-activeSelectionBackground) 55%, transparent); }
  .title { font-size: 12px; font-weight: 700; }
  .meta { font-size: 11px; opacity: 0.75; }
  .msg {
    border: 1px solid var(--vscode-editorWidget-border);
    border-radius: var(--radius-2);
    background: color-mix(in srgb, var(--vscode-editorWidget-background) 92%, transparent);
    padding: var(--space-2);
    display: grid;
    gap: var(--space-1);
  }
  .hdr {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-2);
    font-size: 11px;
    opacity: 0.82;
  }
  .role { font-weight: 700; }
  .content {
    margin: 0;
    white-space: pre-wrap;
    word-break: break-word;
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
    font-size: 11px;
    line-height: 1.45;
    max-height: 420px;
    overflow: auto;
  }
  .empty { opacity: 0.72; padding: var(--space-2); font-size: 12px; }
  @media (max-width: 520px) {
    .container { grid-template-columns: 1fr; }
    .left { max-height: 220px; border-right: 0; border-bottom: 1px solid var(--vscode-editorWidget-border); }
    .right { padding: var(--space-2); }
  }
</style>
</head>
<body>
<div class="header">
  <strong>Axon Chat</strong>
  <button class="btn" id="refresh">Refresh</button>
</div>
<div class="container">
  <aside class="left">
    ${conversationsHtml || '<div class="empty">No conversations</div>'}
  </aside>
  <main class="right">
    ${messagesHtml || '<div class="empty">No messages</div>'}
  </main>
</div>
<script nonce="${nonce}">
const vscode = acquireVsCodeApi();
document.getElementById('refresh')?.addEventListener('click', () => vscode.postMessage({ type: 'refresh' }));
document.querySelectorAll('[data-conv]').forEach((btn) => {
  btn.addEventListener('click', () => {
    vscode.postMessage({ type: 'selectConversation', conversationId: btn.getAttribute('data-conv') });
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
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function escapeHtmlAttr(str: string) {
  return escapeHtml(str);
}
