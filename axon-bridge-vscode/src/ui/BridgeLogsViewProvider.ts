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
    token: vscode.CancellationToken
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
          this.exportToClipboard();
          break;
      }
    });

    this.pushEntries();
  }

  reveal() {
    // Best-effort: focus the container/view.
    vscode.commands.executeCommand('workbench.view.extension.axonBridge');
  }

  notifyNewEntry() {
    this.pushEntries();
  }

  private pushEntries() {
    if (!this.view) return;
    const entries = BridgeLogService.shared.getFilteredEntries(this.filter);
    this.view.webview.postMessage({ type: 'entries', entries });
  }

  private async exportToClipboard() {
    const json = BridgeLogService.shared.export();
    await vscode.env.clipboard.writeText(json);
    vscode.window.showInformationMessage('Axon Bridge Logs copied to clipboard');
  }

  private getHtml(webview: vscode.Webview): string {
    // Same HTML as the panel version; no backticks inside.
    return `<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 0; padding: 0; }
  .toolbar { padding: 10px; border-bottom: 1px solid rgba(127,127,127,.3); }
  .toolbar-row { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 8px; }
  input[type="text"] { width: 100%; padding: 6px 8px; }
  .checks { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; font-size: 12px; }
  .list { overflow: auto; height: calc(100vh - 140px); }
  .entry { padding: 8px 10px; cursor: pointer; border-bottom: 1px solid rgba(127,127,127,.15); }
  .entry:hover { background: rgba(127,127,127,.08); }
  .entry.selected { background: rgba(100, 150, 255, .15); }
  .meta { font-size: 12px; opacity: .85; display: flex; justify-content: space-between; gap: 8px; }
  .summary { font-size: 13px; margin-top: 4px; }
  .pill { font-size: 11px; padding: 1px 6px; border-radius: 999px; border: 1px solid rgba(127,127,127,.3); }
  pre { white-space: pre; overflow: auto; padding: 10px; border: 1px solid rgba(127,127,127,.3); border-radius: 6px; margin: 10px; }
  .errors { color: #b00020; margin: 10px; }
  button { padding: 6px 10px; }
</style>
</head>
<body>
  <div class="toolbar">
    <div class="toolbar-row">
      <button id="btnRefresh">Refresh</button>
      <button id="btnClear">Clear</button>
      <button id="btnExport">Copy JSON</button>
      <button id="btnOutput">Output</button>
    </div>
    <div class="toolbar-row">
      <input id="search" type="text" placeholder="Filter (method, id, json)" />
    </div>
    <div class="checks">
      <label><input type="checkbox" id="showIncoming" checked /> Incoming</label>
      <label><input type="checkbox" id="showOutgoing" checked /> Outgoing</label>
      <label><input type="checkbox" id="showRequests" checked /> Requests</label>
      <label><input type="checkbox" id="showResponses" checked /> Responses</label>
      <label><input type="checkbox" id="showNotifications" checked /> Notifications</label>
      <label><input type="checkbox" id="showErrors" checked /> Errors</label>
      <label><input type="checkbox" id="onlyShowInvalid" /> Only invalid</label>
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

    if (selectedId && !entries.some(e => e.id === selectedId)) {
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
