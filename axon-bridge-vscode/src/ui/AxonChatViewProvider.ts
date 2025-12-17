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
      return { error: "Not connected to Axon. Use “Axon: Connect to Bridge”." };
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
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; padding: 12px; color: var(--vscode-foreground); }
.card { border: 1px solid var(--vscode-editorWidget-border); border-radius: 10px; padding: 12px; background: var(--vscode-editorWidget-background); }
button.primary { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: 0; border-radius: 6px; padding: 6px 10px; }
</style>
</head>
<body>
<div class="card">
<h3>Axon Chat</h3>
<p>${escapeHtml(state.error)}</p>
<button class="primary" id="refresh">Refresh</button>
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
        return `<button class="conv ${isSelected ? "selected" : ""}" data-conv="${escapeHtmlAttr(c.id)}">
    <div class="title">${escapeHtml(title)}</div>
    <div class="meta">${escapeHtml(c.updatedAt ?? "")}</div>
</button>`;
      })
      .join("");

    const messagesHtml = (state.messages?.messages ?? [])
      .map((m) => {
        return `<div class="msg">
    <div class="hdr">
        <span class="role">${escapeHtml(m.role)}</span>
        <span class="time">${escapeHtml(m.createdAt ?? "")}</span>
    </div>
    <pre class="content">${escapeHtml(m.content ?? "")}</pre>
</div>`;
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
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; padding: 0; margin: 0; color: var(--vscode-foreground); }
.header { padding: 10px 12px; border-bottom: 1px solid var(--vscode-editorWidget-border); display:flex; align-items:center; justify-content: space-between; background: var(--vscode-sideBar-background); }
button.primary { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: 0; border-radius: 6px; padding: 6px 10px; cursor:pointer; }
.container { display: grid; grid-template-columns: 220px 1fr; height: calc(100vh - 44px); }
.left { border-right: 1px solid var(--vscode-editorWidget-border); overflow: auto; background: var(--vscode-sideBar-background); }
.right { overflow: auto; padding: 12px; }
.conv { width: 100%; text-align: left; border: 0; padding: 10px 10px; cursor: pointer; background: transparent; color: var(--vscode-foreground); border-bottom: 1px solid rgba(127,127,127,0.15); }
.conv:hover { background: rgba(127,127,127,0.08); }
.conv.selected { background: rgba(127,127,127,0.15); }
.title { font-weight: 600; font-size: 13px; }
.meta { font-size: 11px; opacity: 0.75; margin-top: 2px; }
.msg { border: 1px solid var(--vscode-editorWidget-border); border-radius: 10px; padding: 10px 10px; background: var(--vscode-editorWidget-background); margin-bottom: 10px; }
.hdr { display:flex; justify-content: space-between; gap: 8px; margin-bottom: 8px; font-size: 12px; opacity: 0.85; }
.role { font-weight: 700; }
.content { margin: 0; white-space: pre-wrap; word-break: break-word; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace; }
.empty { opacity: 0.7; }
</style>
</head>
<body>
<div class="header">
  <div><strong>Axon Chat</strong></div>
  <button class="primary" id="refresh">Refresh</button>
</div>
<div class="container">
  <div class="left">
    ${conversationsHtml || '<div class="empty" style="padding:10px;">No conversations</div>'}
  </div>
  <div class="right">
    ${messagesHtml || '<div class="empty">No messages</div>'}
  </div>
</div>
<script nonce="${nonce}">
const vscode = acquireVsCodeApi();
document.getElementById('refresh')?.addEventListener('click', () => vscode.postMessage({ type: 'refresh' }));
document.querySelectorAll('[data-conv]').forEach(btn => {
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
    .replace(/&/g, "&")
    .replace(/</g, "<")
    .replace(/>/g, ">")
    .replace(/"/g, '"')
    .replace(/'/g, "&#039;");
}

function escapeHtmlAttr(str: string) {
  return escapeHtml(str);
}
