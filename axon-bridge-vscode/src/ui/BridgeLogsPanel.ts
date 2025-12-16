/**
 * BridgeLogsPanel.ts
 *
 * Webview panel that mirrors Axon's Bridge Logs UI (simplified):
 * - Filters (direction, type, invalid-only)
 * - Search
 * - List of entries
 * - Detail view w/ pretty JSON + validation errors
 */

import * as vscode from 'vscode';
import { BridgeLogFilter, BridgeLogService } from '../BridgeLogService';

export class BridgeLogsPanel {
  static currentPanel: BridgeLogsPanel | undefined;

  private readonly panel: vscode.WebviewPanel;
  private readonly disposables: vscode.Disposable[] = [];

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

  static show(extensionUri: vscode.Uri) {
    if (BridgeLogsPanel.currentPanel) {
      BridgeLogsPanel.currentPanel.panel.reveal(vscode.ViewColumn.Two);
      BridgeLogsPanel.currentPanel.refresh();
      return;
    }

    const panel = vscode.window.createWebviewPanel(
      'axonBridgeLogs',
      'Axon Bridge Logs',
      vscode.ViewColumn.Two,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
      }
    );

    BridgeLogsPanel.currentPanel = new BridgeLogsPanel(panel, extensionUri);
  }

  private constructor(panel: vscode.WebviewPanel, extensionUri: vscode.Uri) {
    this.panel = panel;
    this.panel.webview.html = this.getHtml(this.panel.webview, extensionUri);

    this.panel.onDidDispose(() => this.dispose(), null, this.disposables);

    this.panel.webview.onDidReceiveMessage(
      (msg) => {
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
      },
      null,
      this.disposables
    );

    this.refresh();
  }

  refresh() {
    this.pushEntries();
  }

  notifyNewEntry() {
    this.pushEntries();
  }

  private pushEntries() {
    const entries = BridgeLogService.shared.getFilteredEntries(this.filter);
    this.panel.webview.postMessage({ type: 'entries', entries });
  }

  private async exportToClipboard() {
    const json = BridgeLogService.shared.export();
    await vscode.env.clipboard.writeText(json);
    vscode.window.showInformationMessage('Axon Bridge Logs copied to clipboard');
  }

  private getHtml(webview: vscode.Webview, extensionUri: vscode.Uri): string {
    // IMPORTANT: Avoid backticks inside this template literal. Use string concatenation in JS.
    return `<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 0; padding: 0; }
  .container { display: grid; grid-template-columns: 380px 1fr; height: 100vh; }
  .left { border-right: 1px solid rgba(127,127,127,.3); display: flex; flex-direction: column; }
  .toolbar { padding: 10px; border-bottom: 1px solid rgba(127,127,127,.3); }
  .toolbar-row { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 8px; }
  input[type="text"] { width: 100%; padding: 6px 8px; }
  .checks { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; font-size: 12px; }
  .list { overflow: auto; flex: 1; }
  .entry { padding: 8px 10px; cursor: pointer; border-bottom: 1px solid rgba(127,127,127,.15); }
  .entry:hover { background: rgba(127,127,127,.08); }
  .entry.selected { background: rgba(100, 150, 255, .15); }
  .meta { font-size: 12px; opacity: .85; display: flex; justify-content: space-between; gap: 8px; }
  .summary { font-size: 13px; margin-top: 4px; }
  .pill { font-size: 11px; padding: 1px 6px; border-radius: 999px; border: 1px solid rgba(127,127,127,.3); }
  .right { overflow: auto; padding: 12px 14px; }
  pre { white-space: pre; overflow: auto; padding: 10px; border: 1px solid rgba(127,127,127,.3); border-radius: 6px; }
  .errors { color: #b00020; margin-top: 10px; }
  button { padding: 6px 10px; }
</style>
</head>
<body>
<div class="container">
  <div class="left">
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
  </div>
  <div class="right">
    <div id="detailEmpty">Select a log entry to view details.</div>
    <div id="detail" style="display:none;">
      <div class="meta" id="detailMeta"></div>
      <div class="summary" id="detailSummary"></div>
      <pre id="detailJson"></pre>
      <div class="errors" id="detailErrors"></div>
    </div>
  </div>
</div>
<script>
  const vscode = acquireVsCodeApi();

  let entries = [];
  let selectedId = null;

  const elList = document.getElementById('list');
  const elSearch = document.getElementById('search');

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

      const left = document.createElement('div');
      left.className = 'meta';
      left.innerHTML = '<span>' + time + ' ' + dir + '</span><span class="pill">' + type + '</span>';

      const sum = document.createElement('div');
      sum.className = 'summary';
      sum.textContent = summaryFor(e);

      row.appendChild(left);
      row.appendChild(sum);

      row.addEventListener('click', () => {
        selectedId = e.id;
        renderList();
        renderDetail(e);
      });

      elList.appendChild(row);
    }

    if (selectedId) {
      const selected = entries.find(x => x.id === selectedId);
      if (selected) renderDetail(selected);
    }
  }

  function renderDetail(e) {
    document.getElementById('detailEmpty').style.display = 'none';
    document.getElementById('detail').style.display = 'block';

    const dir = e.direction === 'outgoing' ? '→ outgoing' : '← incoming';
    document.getElementById('detailMeta').textContent = new Date(e.timestamp).toLocaleString() + '  |  ' + dir + '  |  ' + e.messageType;
    document.getElementById('detailSummary').textContent = summaryFor(e);
    document.getElementById('detailJson').textContent = e.prettyJSON;

    const errEl = document.getElementById('detailErrors');
    if (!e.isValid && e.validationErrors && e.validationErrors.length) {
      errEl.textContent = 'Validation: ' + e.validationErrors.join(' | ');
    } else {
      errEl.textContent = '';
    }
  }

  window.addEventListener('message', (event) => {
    const msg = event.data;
    if (msg.type === 'entries') {
      entries = msg.entries || [];
      if (selectedId && !entries.some(e => e.id === selectedId)) {
        selectedId = null;
        document.getElementById('detailEmpty').style.display = 'block';
        document.getElementById('detail').style.display = 'none';
      }
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

  dispose() {
    BridgeLogsPanel.currentPanel = undefined;

    while (this.disposables.length) {
      const d = this.disposables.pop();
      if (d) d.dispose();
    }

    this.panel.dispose();
  }
}
