/**
 * BridgeLogsViewProvider.ts
 *
 * True VS Code Side Bar view (WebviewViewProvider) for Axon Bridge Logs.
 * This makes logs show up in the left Activity Bar (Axon container).
 */

import * as vscode from 'vscode';
import { BridgeLogFilter, BridgeLogService } from '../BridgeLogService';

export class BridgeLogsViewProvider implements vscode.WebviewViewProvider {
  static readonly viewType = 'axonBridgeLogsView';
  static shared: BridgeLogsViewProvider | undefined;

  private view?: vscode.WebviewView;

  private filter: BridgeLogFilter = {
    filterText: '',
    showIncoming: true,
    showOutgoing: true,
    showRequests: true,
    showResponses: true,
    showNotifications: true,
    showErrors: true,
    onlyShowInvalid: false,
  };

  resolveWebviewView(
    webviewView: vscode.WebviewView,
    context: vscode.WebviewViewResolveContext,
    token: vscode.CancellationToken,
  ): void {
    BridgeLogsViewProvider.shared = this;
    this.view = webviewView;

    webviewView.webview.options = {
      enableScripts: true,
    };

    webviewView.webview.html = this.getHtml(webviewView.webview);

    webviewView.webview.onDidReceiveMessage((msg) => {
      switch (msg?.type) {
        case 'setFilter':
          this.filter = {
            ...this.filter,
            ...msg.filter,
          };
          this.pushEntries();
          break;
        case 'requestEntries':
          this.pushEntries();
          break;
        case 'clear':
          BridgeLogService.shared.clear();
          this.pushEntries();
          break;
        case 'showOutput':
          BridgeLogService.shared.showOutput();
          break;
        case 'export':
          void this.exportToClipboard();
          break;
      }
    });

    this.pushEntries();
  }

  reveal() {
    // Best-effort: focus the container/view.
    void vscode.commands.executeCommand('workbench.view.extension.axonBridge');
  }

  notifyNewEntry() {
    this.pushEntries();
  }

  private pushEntries() {
    if (!this.view) return;
    const entries = BridgeLogService.shared.getFilteredEntries(this.filter);
    void this.view.webview.postMessage({ type: 'entries', entries });
  }

  private async exportToClipboard() {
    const json = BridgeLogService.shared.export();
    await vscode.env.clipboard.writeText(json);
    vscode.window.showInformationMessage('Axon Bridge Logs copied to clipboard');
  }

  private getHtml(webview: vscode.Webview): string {
    return `<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
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
    background: linear-gradient(155deg, color-mix(in srgb, var(--vscode-sideBar-background) 90%, transparent), var(--vscode-editor-background));
    font-family: "Avenir Next", "Segoe UI", "Helvetica Neue", sans-serif;
  }
  .toolbar {
    position: sticky;
    top: 0;
    z-index: 1;
    padding: var(--space-2);
    border-bottom: 1px solid var(--vscode-editorWidget-border);
    background: color-mix(in srgb, var(--vscode-sideBar-background) 90%, transparent);
    display: grid;
    gap: var(--space-2);
  }
  .toolbar-row {
    display: flex;
    gap: var(--space-1);
    flex-wrap: wrap;
  }
  button {
    border-radius: var(--radius-1);
    border: 1px solid transparent;
    background: var(--vscode-button-background);
    color: var(--vscode-button-foreground);
    padding: 6px 9px;
    cursor: pointer;
    font-size: 11px;
  }
  button.subtle {
    border-color: var(--vscode-editorWidget-border);
    background: transparent;
    color: var(--vscode-foreground);
  }
  input[type="text"] {
    width: 100%;
    border-radius: var(--radius-1);
    border: 1px solid var(--vscode-input-border);
    background: var(--vscode-input-background);
    color: var(--vscode-input-foreground);
    padding: 7px 10px;
    font: inherit;
  }
  .checks {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 6px;
    font-size: 11px;
  }
  .checks label {
    display: flex;
    align-items: center;
    gap: 6px;
    opacity: 0.92;
  }
  .list {
    overflow: auto;
    height: calc(100vh - 196px);
  }
  .entry {
    padding: var(--space-2);
    cursor: pointer;
    border-bottom: 1px solid color-mix(in srgb, var(--vscode-editorWidget-border) 72%, transparent);
    background: transparent;
  }
  .entry:hover {
    background: color-mix(in srgb, var(--vscode-list-hoverBackground) 72%, transparent);
  }
  .entry.selected {
    background: color-mix(in srgb, var(--vscode-list-activeSelectionBackground) 62%, transparent);
  }
  .meta {
    font-size: 11px;
    opacity: 0.82;
    display: flex;
    justify-content: space-between;
    gap: 8px;
  }
  .summary {
    font-size: 12px;
    margin-top: 4px;
    word-break: break-word;
  }
  .pill {
    font-size: 10px;
    padding: 1px 7px;
    border-radius: 999px;
    border: 1px solid var(--vscode-editorWidget-border);
  }
  pre {
    white-space: pre-wrap;
    word-break: break-word;
    overflow: auto;
    margin: var(--space-2);
    border-radius: var(--radius-2);
    border: 1px solid var(--vscode-editorWidget-border);
    padding: var(--space-2);
    background: color-mix(in srgb, var(--vscode-editorWidget-background) 92%, transparent);
    font-size: 11px;
    max-height: 280px;
  }
  .errors {
    margin: 0 var(--space-2) var(--space-2) var(--space-2);
    color: var(--vscode-inputValidation-errorForeground);
    font-size: 11px;
  }
  @media (max-width: 430px) {
    .checks { grid-template-columns: 1fr; }
    button { flex: 1; }
  }
</style>
</head>
<body>
  <div class="toolbar">
    <div class="toolbar-row">
      <button id="btnRefresh">Refresh</button>
      <button id="btnClear" class="subtle">Clear</button>
      <button id="btnExport" class="subtle">Copy JSON</button>
      <button id="btnOutput" class="subtle">Output</button>
    </div>
    <div class="toolbar-row">
      <input id="search" type="text" placeholder="Filter by method, id, payload" />
    </div>
    <div class="checks">
      <label><input type="checkbox" id="showIncoming" checked /> Incoming</label>
      <label><input type="checkbox" id="showOutgoing" checked /> Outgoing</label>
      <label><input type="checkbox" id="showRequests" checked /> Requests</label>
      <label><input type="checkbox" id="showResponses" checked /> Responses</label>
      <label><input type="checkbox" id="showNotifications" checked /> Notifications</label>
      <label><input type="checkbox" id="showErrors" checked /> Errors</label>
      <label><input type="checkbox" id="onlyShowInvalid" /> Only Invalid</label>
    </div>
  </div>

  <div id="list" class="list"></div>
  <pre id="detailJson" style="display:none;"></pre>
  <div class="errors" id="detailErrors"></div>

<script>
  const vscode = acquireVsCodeApi();

  let entries = [];
  let selectedId = null;

  const elList = document.getElementById('list');
  const elSearch = document.getElementById('search');
  const elDetail = document.getElementById('detailJson');

  function currentFilter() {
    return {
      filterText: elSearch.value || '',
      showIncoming: document.getElementById('showIncoming').checked,
      showOutgoing: document.getElementById('showOutgoing').checked,
      showRequests: document.getElementById('showRequests').checked,
      showResponses: document.getElementById('showResponses').checked,
      showNotifications: document.getElementById('showNotifications').checked,
      showErrors: document.getElementById('showErrors').checked,
      onlyShowInvalid: document.getElementById('onlyShowInvalid').checked,
    };
  }

  function emitFilter() {
    vscode.postMessage({ type: 'setFilter', filter: currentFilter() });
  }

  function summaryFor(e) {
    if (e.method) return e.method;
    if (e.messageType === 'response') return 'response ' + (e.requestId || '');
    return e.messageType;
  }

  function renderList() {
    elList.innerHTML = '';
    for (const e of entries) {
      const row = document.createElement('div');
      row.className = 'entry' + (e.id === selectedId ? ' selected' : '');

      const d = new Date(e.timestamp);
      const time = d.toLocaleTimeString() + '.' + String(e.timestamp % 1000).padStart(3, '0');
      const dir = e.direction === 'outgoing' ? '→' : '←';
      const type = e.messageType;

      const meta = document.createElement('div');
      meta.className = 'meta';
      meta.innerHTML = '<span>' + time + ' ' + dir + '</span><span class="pill">' + type + '</span>';

      const sum = document.createElement('div');
      sum.className = 'summary';
      sum.textContent = summaryFor(e);

      row.appendChild(meta);
      row.appendChild(sum);

      row.addEventListener('click', () => {
        selectedId = e.id;
        renderList();
        elDetail.style.display = 'block';
        elDetail.textContent = e.prettyJSON;

        const errEl = document.getElementById('detailErrors');
        if (!e.isValid && e.validationErrors && e.validationErrors.length) {
          errEl.textContent = 'Validation: ' + e.validationErrors.join(' | ');
        } else {
          errEl.textContent = '';
        }
      });

      elList.appendChild(row);
    }

    if (selectedId && !entries.some((e) => e.id === selectedId)) {
      selectedId = null;
      elDetail.style.display = 'none';
      document.getElementById('detailErrors').textContent = '';
    }
  }

  window.addEventListener('message', (event) => {
    const msg = event.data;
    if (msg.type === 'entries') {
      entries = msg.entries || [];
      renderList();
    }
  });

  document.getElementById('btnRefresh').addEventListener('click', () => vscode.postMessage({ type: 'requestEntries' }));
  document.getElementById('btnClear').addEventListener('click', () => vscode.postMessage({ type: 'clear' }));
  document.getElementById('btnExport').addEventListener('click', () => vscode.postMessage({ type: 'export' }));
  document.getElementById('btnOutput').addEventListener('click', () => vscode.postMessage({ type: 'showOutput' }));

  elSearch.addEventListener('input', emitFilter);
  for (const id of ['showIncoming','showOutgoing','showRequests','showResponses','showNotifications','showErrors','onlyShowInvalid']) {
    document.getElementById(id).addEventListener('change', emitFilter);
  }

  vscode.postMessage({ type: 'requestEntries' });
</script>
</body>
</html>`;
  }
}
