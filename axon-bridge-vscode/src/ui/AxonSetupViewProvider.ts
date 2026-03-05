import * as os from "os";
import * as vscode from "vscode";
import QRCode from "qrcode";
import { BridgeClient } from "../BridgeClient";
import { BridgeConnectionManager } from "../BridgeConnectionManager";
import { BridgeMode, BridgePairingInfo } from "../Protocol";
import { ConnectionProfileManager } from "../ConnectionProfileManager";
import { TrustedCertManager } from "../TrustedCertManager";

type SetupUrl = {
  label: string;
  url: string;
  address: string;
  source: "lan" | "fallback";
};

type SetupSnapshot = {
  mode: BridgeMode;
  networkingEnabled: boolean;
  serverRunning: boolean;
  clientCount: number;
  serverPort: number;
  tlsEnabled: boolean;
  pairingTokenPresent: boolean;
  urls: SetupUrl[];
  primaryUrl?: string;
  qrPayload?: string;
  qrDataUrl?: string;
  localPairingInfo?: BridgePairingInfo;
};

/**
 * AxonSetupViewProvider
 *
 * Interactive setup/status view for local and remote bridge networking.
 */
export class AxonSetupViewProvider implements vscode.WebviewViewProvider {
  public static readonly viewType = "axonSetupView";

  private view?: vscode.WebviewView;
  private inlineError?: string;
  private refreshTimer?: NodeJS.Timeout;

  constructor(
    private readonly context: vscode.ExtensionContext,
    private readonly connectionManagerProvider: () =>
      | BridgeConnectionManager
      | undefined,
    private readonly clientProvider: () => BridgeClient | undefined,
  ) {
    this.context.subscriptions.push(
      vscode.workspace.onDidChangeConfiguration((e) => {
        if (e.affectsConfiguration("axonBridge")) {
          void this.render();
        }
      }),
    );
  }

  resolveWebviewView(webviewView: vscode.WebviewView): void {
    this.view = webviewView;

    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [this.context.extensionUri],
    };

    webviewView.webview.onDidReceiveMessage(async (message) => {
      switch (message.type) {
        case "refresh":
          this.inlineError = undefined;
          await this.render();
          break;

        case "copy":
          if (typeof message.text === "string") {
            await vscode.env.clipboard.writeText(message.text);
            vscode.window.showInformationMessage("Copied to clipboard");
          }
          break;

        case "copyAllUrls":
          if (Array.isArray(message.urls)) {
            const urls = (message.urls as unknown[]).filter(
              (v: unknown): v is string => typeof v === "string",
            );
            if (urls.length > 0) {
              await vscode.env.clipboard.writeText(urls.join("\n"));
              vscode.window.showInformationMessage("All server URLs copied");
            }
          }
          break;

        case "toggleNetworking": {
          await this.handleToggleNetworking(message.enabled === true);
          break;
        }

        case "savePort": {
          await this.handleSavePort(message.port);
          break;
        }

        case "importQRPayload": {
          await this.handleImportQRPayload(message.payload);
          break;
        }

        case "addProfile": {
          await this.handleAddProfile(message.name, message.host, message.port, message.tlsEnabled);
          break;
        }

        case "connectToProfile": {
          await this.handleConnectToProfile(message.profileId);
          break;
        }

        case "setDefaultProfile": {
          ConnectionProfileManager.setDefaultProfile(message.profileId ?? null);
          await this.render();
          break;
        }

        case "deleteProfile": {
          ConnectionProfileManager.deleteProfile(message.profileId);
          await this.render();
          break;
        }

        case "addTrustedFingerprint": {
          await this.handleAddTrustedFingerprint(message.fingerprint);
          break;
        }

        case "removeTrustedFingerprint": {
          TrustedCertManager.removeTrustedFingerprint(message.fingerprint);
          await this.render();
          break;
        }
      }
    });

    this.startRefreshTimer();
    webviewView.onDidDispose(() => {
      this.stopRefreshTimer();
      this.view = undefined;
    });

    void this.render();
  }

  reveal() {
    this.view?.show?.(true);
  }

  private startRefreshTimer() {
    this.stopRefreshTimer();
    this.refreshTimer = setInterval(() => {
      if (this.view?.visible) {
        void this.render();
      }
    }, 2000);
  }

  private stopRefreshTimer() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = undefined;
    }
  }

  private async handleToggleNetworking(enable: boolean) {
    const manager = this.connectionManagerProvider();
    if (!manager) {
      this.inlineError = "Bridge connection manager is not available yet.";
      await this.render();
      return;
    }

    try {
      this.inlineError = undefined;
      if (enable) {
        await manager.enableRemoteNetworking();
      } else {
        await manager.disableRemoteNetworking();
      }
    } catch (e) {
      this.inlineError = e instanceof Error ? e.message : String(e);
    }

    await this.render();
  }

  private async handleSavePort(rawPort: unknown) {
    const parsed = Number(rawPort);
    if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) {
      this.inlineError = "Invalid port. Enter an integer between 1 and 65535.";
      await this.render();
      return;
    }

    const manager = this.connectionManagerProvider();

    try {
      this.inlineError = undefined;
      if (!manager) {
        const config = vscode.workspace.getConfiguration("axonBridge");
        await config.update(
          "serverPort",
          parsed,
          vscode.ConfigurationTarget.Global,
        );
      } else {
        await manager.updateServerPort(parsed, vscode.ConfigurationTarget.Global);
      }
      vscode.window.showInformationMessage(`Axon server port updated to ${parsed}`);
    } catch (e) {
      this.inlineError = e instanceof Error ? e.message : String(e);
    }

    await this.render();
  }

  private async handleImportQRPayload(rawPayload: unknown) {
    const payload = typeof rawPayload === "string" ? rawPayload.trim() : "";
    if (!payload) {
      this.inlineError = "Enter a ws:// or wss:// URL to import.";
      await this.render();
      return;
    }

    const profile = ConnectionProfileManager.importFromQRPayload(payload);
    if (!profile) {
      this.inlineError = "Invalid QR payload. Expected format: ws://host:port or wss://host:port?pairingToken=TOKEN";
      await this.render();
      return;
    }

    // If the payload included a pairing token, apply it to settings
    const parsed = ConnectionProfileManager.parseQRPayload(payload);
    if (parsed?.pairingToken) {
      const config = vscode.workspace.getConfiguration("axonBridge");
      await config.update("pairingToken", parsed.pairingToken, vscode.ConfigurationTarget.Global);
    }

    this.inlineError = undefined;
    vscode.window.showInformationMessage(`Imported profile "${profile.name}"`);
    await this.render();
  }

  private async handleAddProfile(rawName: unknown, rawHost: unknown, rawPort: unknown, rawTls: unknown) {
    const name = typeof rawName === "string" ? rawName.trim() : "";
    const host = typeof rawHost === "string" ? rawHost.trim() : "";
    const port = Number(rawPort);
    const tlsEnabled = rawTls === true;

    if (!name || !host) {
      this.inlineError = "Name and host are required.";
      await this.render();
      return;
    }

    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      this.inlineError = "Port must be between 1 and 65535.";
      await this.render();
      return;
    }

    ConnectionProfileManager.addProfile(name, host, port, tlsEnabled);
    this.inlineError = undefined;
    await this.render();
  }

  private async handleConnectToProfile(rawId: unknown) {
    const profileId = typeof rawId === "string" ? rawId : "";
    if (!profileId) return;

    const manager = this.connectionManagerProvider();
    if (!manager) {
      this.inlineError = "Bridge connection manager is not available yet.";
      await this.render();
      return;
    }

    try {
      this.inlineError = undefined;
      await manager.connectToProfile(profileId);
    } catch (e) {
      this.inlineError = e instanceof Error ? e.message : String(e);
    }

    await this.render();
  }

  private async handleAddTrustedFingerprint(rawFingerprint: unknown) {
    const fingerprint = typeof rawFingerprint === "string" ? rawFingerprint.trim() : "";
    if (!fingerprint) {
      this.inlineError = "Enter a SHA-256 fingerprint.";
      await this.render();
      return;
    }

    if (!TrustedCertManager.isValidFingerprint(fingerprint)) {
      this.inlineError = "Invalid fingerprint. Expected 64-character hex (SHA-256).";
      await this.render();
      return;
    }

    const added = TrustedCertManager.addTrustedFingerprint(fingerprint);
    if (!added) {
      this.inlineError = "Fingerprint already trusted.";
      await this.render();
      return;
    }

    this.inlineError = undefined;
    await this.render();
  }

  private async fetchLocalPairingInfo(): Promise<BridgePairingInfo | undefined> {
    const client = this.clientProvider();
    if (!client || !client.isConnected()) {
      return undefined;
    }

    try {
      return await client.getPairingInfo();
    } catch {
      return undefined;
    }
  }

  private getRemoteUrls(
    port: number,
    tlsEnabled: boolean,
    bindAddress: string,
  ): SetupUrl[] {
    const scheme = tlsEnabled ? "wss" : "ws";
    const interfaces = os.networkInterfaces();
    const urls: SetupUrl[] = [];

    for (const [name, entries] of Object.entries(interfaces)) {
      for (const iface of entries ?? []) {
        const isIPv4 = iface.family === "IPv4";
        if (!isIPv4 || iface.internal) {
          continue;
        }

        urls.push({
          label: `${name} (${iface.address})`,
          url: `${scheme}://${iface.address}:${port}`,
          address: iface.address,
          source: "lan",
        });
      }
    }

    const unique = new Map<string, SetupUrl>();
    for (const entry of urls) {
      if (!unique.has(entry.url)) {
        unique.set(entry.url, entry);
      }
    }

    const sorted = Array.from(unique.values()).sort((a, b) => {
      const priorityDelta = this.addressPriority(a.address) - this.addressPriority(b.address);
      if (priorityDelta !== 0) return priorityDelta;
      if (a.address !== b.address) return a.address.localeCompare(b.address, undefined, { numeric: true });
      if (a.url !== b.url) return a.url.localeCompare(b.url);
      return a.label.localeCompare(b.label);
    });

    if (sorted.length > 0) {
      return sorted;
    }

    const fallbackHost = bindAddress === "0.0.0.0" ? "localhost" : bindAddress;
    return [
      {
        label: "Fallback",
        url: `${scheme}://${fallbackHost}:${port}`,
        address: fallbackHost,
        source: "fallback",
      },
    ];
  }

  private addressPriority(address: string): number {
    // Prioritize RFC1918 LAN ranges, then other routable IPv4, and place
    // link-local (169.254.x.x) last so QR defaults are more likely reachable.
    if (this.isPrivateIPv4(address)) return 0;
    if (this.isLinkLocalIPv4(address)) return 2;
    return 1;
  }

  private isPrivateIPv4(address: string): boolean {
    if (address.startsWith("10.")) return true;
    if (address.startsWith("192.168.")) return true;
    const octets = address.split(".");
    if (octets.length !== 4) return false;
    const first = Number.parseInt(octets[0], 10);
    const second = Number.parseInt(octets[1], 10);
    return first === 172 && second >= 16 && second <= 31;
  }

  private isLinkLocalIPv4(address: string): boolean {
    return address.startsWith("169.254.");
  }

  private buildQrPayload(baseUrl: string, pairingToken?: string): string {
    if (!pairingToken?.trim()) {
      return baseUrl;
    }

    const separator = baseUrl.includes("?") ? "&" : "?";
    return `${baseUrl}${separator}pairingToken=${encodeURIComponent(
      pairingToken.trim(),
    )}`;
  }

  private async buildSnapshot(): Promise<SetupSnapshot> {
    const config = vscode.workspace.getConfiguration("axonBridge");
    const manager = this.connectionManagerProvider();

    const mode = manager?.getMode() ?? config.get<BridgeMode>("mode", "local");
    const serverPort = config.get<number>("serverPort", 8082);
    const tlsEnabled = config.get<boolean>("tlsEnabled", false);
    const pairingToken = config.get<string>("pairingToken", "");
    const bindAddress = config.get<string>("serverBindAddress", "0.0.0.0");

    const serverRunning = manager?.isServerRunning() ?? false;
    const urls = this.getRemoteUrls(serverPort, tlsEnabled, bindAddress);
    const primaryUrl = urls[0]?.url;

    let qrPayload: string | undefined;
    let qrDataUrl: string | undefined;

    if (serverRunning && primaryUrl) {
      qrPayload = this.buildQrPayload(primaryUrl, pairingToken);
      try {
        qrDataUrl = await QRCode.toDataURL(qrPayload, {
          errorCorrectionLevel: "M",
          margin: 1,
          width: 220,
        });
      } catch {
        // Keep the page functional even if QR encoding fails.
      }
    }

    return {
      mode,
      networkingEnabled: serverRunning,
      serverRunning,
      clientCount: manager?.getServerClientCount() ?? 0,
      serverPort,
      tlsEnabled,
      pairingTokenPresent: pairingToken.trim().length > 0,
      urls,
      primaryUrl,
      qrPayload,
      qrDataUrl,
      localPairingInfo: await this.fetchLocalPairingInfo(),
    };
  }

  private async render() {
    if (!this.view) return;

    const state = await this.buildSnapshot();
    this.view.webview.html = this.getHtml(state, this.inlineError);
  }

  private getHtml(state: SetupSnapshot, inlineError?: string) {
    const nonce = getNonce();

    const urlsHtml = state.urls
      .map(
        (entry, index) => `<div class="url-item">
  <div class="url-row">
    <span class="url-label">${escapeHtml(entry.label)}</span>
    <span class="pill ${index === 0 ? "pill-primary" : ""}">${
      index === 0 ? "Primary" : "LAN"
    }</span>
  </div>
  <div class="url-copy-row">
    <code>${escapeHtml(entry.url)}</code>
    <button class="btn subtle" data-copy="${escapeHtmlAttr(entry.url)}">Copy</button>
  </div>
</div>`,
      )
      .join("");

    const localPairing = state.localPairingInfo
      ? `<div class="card">
  <div class="card-head">
    <h3>Local Axon Pairing (Read-Only)</h3>
    <span class="pill">Connected</span>
  </div>
  <div class="grid">
    <span class="k">Device</span><span class="v">${escapeHtml(
      state.localPairingInfo.deviceName ?? "Unknown",
    )}</span>
    <span class="k">Axon localhost URL</span>
    <span class="v mono">${escapeHtml(
      state.localPairingInfo.axonBridgeWsLocalhostUrl,
    )}</span>
    <span class="k">Axon Port</span><span class="v mono">${escapeHtml(
      String(state.localPairingInfo.axonBridgePort),
    )}</span>
    <span class="k">Token Required</span><span class="v">${
      state.localPairingInfo.requiredPairingToken ? "Yes" : "No"
    }</span>
    <span class="k">VS Code Connections</span><span class="v">${escapeHtml(
      String(state.localPairingInfo.connectionCount),
    )}</span>
    <span class="k">Axon QR Payload</span>
    <span class="v mono">
      ${escapeHtml(state.localPairingInfo.qrPayload)}
      <button class="btn subtle" data-copy="${escapeHtmlAttr(
        state.localPairingInfo.qrPayload,
      )}">Copy</button>
    </span>
  </div>
</div>`
      : `<div class="card muted-card">
  <div class="card-head">
    <h3>Local Axon Pairing (Read-Only)</h3>
    <span class="pill">Unavailable</span>
  </div>
  <p>Connect to Axon in Local Mode to view pairing metadata mirrored from the app.</p>
</div>`;

    const qrBlock =
      state.networkingEnabled && state.qrDataUrl && state.qrPayload
        ? `<div class="card">
  <div class="card-head">
    <h3>Mobile Auto-Connect QR</h3>
    <span class="pill pill-primary">Live</span>
  </div>
  <div class="qr-wrap">
    <img class="qr" src="${state.qrDataUrl}" alt="Axon remote connection QR code" />
    <div class="qr-meta">
      <div class="k">Payload</div>
      <code>${escapeHtml(state.qrPayload)}</code>
      <button class="btn subtle" data-copy="${escapeHtmlAttr(
        state.qrPayload,
      )}">Copy Payload</button>
    </div>
  </div>
</div>`
        : "";

    // Build profiles section
    const profiles = ConnectionProfileManager.getProfiles();
    const defaultProfileId = ConnectionProfileManager.getDefaultProfileId();
    const profilesHtml = profiles.length > 0
      ? profiles.map((p) => {
        const isDefault = p.id === defaultProfileId;
        const scheme = p.tlsEnabled ? "wss" : "ws";
        const lastConn = p.lastConnectedAt
          ? new Date(p.lastConnectedAt).toLocaleDateString()
          : "Never";
        return `<div class="url-item">
  <div class="url-row">
    <span class="url-label">${escapeHtml(p.name)}${isDefault ? ' <span class="pill pill-primary">Default</span>' : ""}</span>
    <span class="pill">${escapeHtml(scheme)}</span>
  </div>
  <div class="url-copy-row">
    <code>${escapeHtml(`${scheme}://${p.host}:${p.port}`)}</code>
    <span class="profile-actions">
      <button class="btn subtle" data-connect-profile="${escapeHtmlAttr(p.id)}">Connect</button>
      ${!isDefault ? `<button class="btn subtle" data-set-default="${escapeHtmlAttr(p.id)}">Set Default</button>` : ""}
      <button class="btn subtle" data-delete-profile="${escapeHtmlAttr(p.id)}">Delete</button>
    </span>
  </div>
  <div class="url-row">
    <span class="url-label">Last connected: ${escapeHtml(lastConn)}</span>
  </div>
</div>`;
      }).join("")
      : `<p>No saved profiles. Import a QR payload or add one manually.</p>`;

    // Build trusted certs section
    const trustedFingerprints = TrustedCertManager.getTrustedFingerprints();
    const trustedCertsHtml = trustedFingerprints.length > 0
      ? trustedFingerprints.map((fp) => {
        const formatted = TrustedCertManager.formatFingerprint(fp);
        const short = formatted.length > 32 ? formatted.substring(0, 32) + "..." : formatted;
        return `<div class="url-item">
  <div class="url-copy-row">
    <code title="${escapeHtmlAttr(formatted)}">${escapeHtml(short)}</code>
    <span class="profile-actions">
      <button class="btn subtle" data-copy="${escapeHtmlAttr(formatted)}">Copy</button>
      <button class="btn subtle" data-remove-fingerprint="${escapeHtmlAttr(fp)}">Remove</button>
    </span>
  </div>
</div>`;
      }).join("")
      : `<p>No trusted certificates. Add fingerprints for self-signed TLS certs.</p>`;

    const urlValues = JSON.stringify(state.urls.map((u) => u.url));

    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';" />
  <title>Axon Setup</title>
  <style>
    :root {
      --space-1: 6px;
      --space-2: 10px;
      --space-3: 14px;
      --space-4: 18px;
      --radius-1: 10px;
      --radius-2: 14px;
      --shadow: 0 1px 0 rgba(0,0,0,0.18);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: var(--space-3);
      color: var(--vscode-foreground);
      background: linear-gradient(140deg, color-mix(in srgb, var(--vscode-sideBar-background) 90%, transparent), var(--vscode-editor-background));
      font-family: "Avenir Next", "Segoe UI", "Helvetica Neue", sans-serif;
      display: grid;
      gap: var(--space-3);
    }
    .card {
      border: 1px solid var(--vscode-editorWidget-border);
      border-radius: var(--radius-2);
      background: color-mix(in srgb, var(--vscode-editorWidget-background) 92%, transparent);
      padding: var(--space-3);
      box-shadow: var(--shadow);
      display: grid;
      gap: var(--space-3);
    }
    .muted-card { opacity: 0.9; }
    .card-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: var(--space-2);
    }
    h2, h3 { margin: 0; }
    h2 { font-size: 15px; letter-spacing: 0.2px; }
    h3 { font-size: 13px; }
    p { margin: 0; opacity: 0.9; line-height: 1.45; }
    .toolbar {
      display: flex;
      gap: var(--space-2);
      align-items: center;
      flex-wrap: wrap;
    }
    .pill {
      border: 1px solid var(--vscode-editorWidget-border);
      border-radius: 999px;
      padding: 2px 8px;
      font-size: 11px;
      opacity: 0.9;
    }
    .pill-primary {
      border-color: var(--vscode-textLink-foreground);
      color: var(--vscode-textLink-foreground);
    }
    .btn {
      border: 1px solid transparent;
      border-radius: var(--radius-1);
      padding: 7px 11px;
      cursor: pointer;
      font-size: 12px;
      color: var(--vscode-button-foreground);
      background: var(--vscode-button-background);
    }
    .btn:hover { filter: brightness(1.06); }
    .btn.subtle {
      background: transparent;
      border-color: var(--vscode-editorWidget-border);
      color: var(--vscode-foreground);
    }
    .btn.toggle-on {
      background: color-mix(in srgb, var(--vscode-testing-iconPassed) 30%, var(--vscode-button-background));
      border-color: color-mix(in srgb, var(--vscode-testing-iconPassed) 70%, var(--vscode-editorWidget-border));
    }
    .status-row {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: var(--space-2);
    }
    .metric {
      border: 1px solid var(--vscode-editorWidget-border);
      border-radius: var(--radius-1);
      padding: var(--space-2);
      display: grid;
      gap: 2px;
      background: color-mix(in srgb, var(--vscode-sideBar-background) 76%, transparent);
    }
    .metric .label { font-size: 11px; opacity: 0.75; }
    .metric .value { font-size: 13px; font-weight: 600; }
    .port-row {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: var(--space-2);
      align-items: center;
    }
    input[type="number"] {
      width: 100%;
      border-radius: var(--radius-1);
      border: 1px solid var(--vscode-input-border);
      background: var(--vscode-input-background);
      color: var(--vscode-input-foreground);
      padding: 8px 10px;
      font: inherit;
      min-width: 0;
    }
    .url-list { display: grid; gap: var(--space-2); }
    .url-item {
      border: 1px solid var(--vscode-editorWidget-border);
      border-radius: var(--radius-1);
      padding: var(--space-2);
      display: grid;
      gap: var(--space-1);
      background: color-mix(in srgb, var(--vscode-sideBar-background) 70%, transparent);
    }
    .url-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: var(--space-2);
    }
    .url-label { font-size: 11px; opacity: 0.8; }
    .url-copy-row {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: var(--space-2);
      align-items: center;
    }
    .grid {
      display: grid;
      grid-template-columns: minmax(110px, 0.7fr) minmax(0, 1fr);
      gap: 10px 12px;
      align-items: start;
    }
    .k { font-size: 11px; opacity: 0.78; }
    .v { word-break: break-word; }
    code, .mono {
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      font-size: 11px;
    }
    code {
      padding: 5px 7px;
      border: 1px solid var(--vscode-editorWidget-border);
      border-radius: 8px;
      background: color-mix(in srgb, var(--vscode-editor-background) 86%, transparent);
      display: inline-block;
      word-break: break-all;
    }
    .error {
      border-color: var(--vscode-inputValidation-errorBorder);
      background: color-mix(in srgb, var(--vscode-inputValidation-errorBackground) 65%, transparent);
      color: var(--vscode-inputValidation-errorForeground);
      border-radius: var(--radius-1);
      padding: 8px 10px;
      font-size: 12px;
    }
    .qr-wrap {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr);
      gap: var(--space-3);
      align-items: center;
    }
    .qr {
      width: 120px;
      height: 120px;
      border-radius: 10px;
      border: 1px solid var(--vscode-editorWidget-border);
      background: #fff;
      padding: 4px;
    }
    .qr-meta {
      display: grid;
      gap: var(--space-1);
      min-width: 0;
    }
    .profile-actions {
      display: flex;
      gap: 4px;
      flex-shrink: 0;
    }
    input[type="text"] {
      width: 100%;
      border-radius: var(--radius-1);
      border: 1px solid var(--vscode-input-border);
      background: var(--vscode-input-background);
      color: var(--vscode-input-foreground);
      padding: 8px 10px;
      font: inherit;
      min-width: 0;
    }
    .form-grid {
      display: grid;
      gap: var(--space-2);
    }
    .form-row {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: var(--space-2);
      align-items: center;
    }
    .form-field {
      display: grid;
      gap: 4px;
    }
    .form-field label {
      font-size: 11px;
      opacity: 0.78;
    }
    .form-inline {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: var(--space-2);
    }
    .checkbox-row {
      display: flex;
      align-items: center;
      gap: var(--space-2);
    }
    .checkbox-row label {
      font-size: 12px;
    }
    @media (max-width: 520px) {
      body { padding: var(--space-2); }
      .status-row,
      .port-row,
      .url-copy-row,
      .qr-wrap,
      .grid {
        grid-template-columns: minmax(0, 1fr);
      }
      .toolbar { width: 100%; }
      .toolbar .btn { flex: 1; }
      .card-head { align-items: flex-start; }
    }
  </style>
</head>
<body>
  <section class="card">
    <div class="card-head">
      <h2>Axon Setup</h2>
      <span class="pill ${state.networkingEnabled ? "pill-primary" : ""}">${
      state.networkingEnabled ? "Networking ON" : "Networking OFF"
    }</span>
    </div>

    ${
      inlineError
        ? `<div class="error">${escapeHtml(inlineError)}</div>`
        : ""
    }

    <div class="toolbar">
      <button id="toggleNetworking" class="btn ${
        state.networkingEnabled ? "toggle-on" : ""
      }" data-enabled="${state.networkingEnabled ? "1" : "0"}">
        ${state.networkingEnabled ? "Turn Networking Off" : "Turn Networking On"}
      </button>
      <button id="refresh" class="btn subtle">Refresh</button>
      <button id="copyAllUrls" class="btn subtle">Copy All URLs</button>
    </div>

    <div class="status-row">
      <div class="metric">
        <span class="label">Mode</span>
        <span class="value">${escapeHtml(state.mode)}</span>
      </div>
      <div class="metric">
        <span class="label">Clients</span>
        <span class="value">${escapeHtml(String(state.clientCount))}</span>
      </div>
      <div class="metric">
        <span class="label">TLS</span>
        <span class="value">${state.tlsEnabled ? "Enabled" : "Disabled"}</span>
      </div>
      <div class="metric">
        <span class="label">Pairing Token</span>
        <span class="value">${state.pairingTokenPresent ? "Configured" : "None"}</span>
      </div>
    </div>

    <div>
      <div class="k">Server Port (Global)</div>
      <div class="port-row">
        <input id="portInput" type="number" min="1" max="65535" value="${escapeHtmlAttr(
          String(state.serverPort),
        )}" />
        <button id="savePort" class="btn">Save Port</button>
      </div>
    </div>

    <div>
      <div class="k">LAN Server URLs</div>
      <div class="url-list">${urlsHtml}</div>
    </div>
  </section>

  ${qrBlock}

  ${localPairing}

  <section class="card">
    <div class="card-head">
      <h3>Connection Profiles</h3>
      <span class="pill">${escapeHtml(String(profiles.length))} saved</span>
    </div>
    <div class="url-list">${profilesHtml}</div>
  </section>

  <section class="card">
    <div class="card-head">
      <h3>Import QR Payload</h3>
    </div>
    <p>Paste a <code>ws://</code> or <code>wss://</code> URL from an Axon QR code to create a profile.</p>
    <div class="form-row">
      <input id="qrPayloadInput" type="text" placeholder="ws://192.168.1.x:8081?pairingToken=..." />
      <button id="importQRBtn" class="btn">Import</button>
    </div>
  </section>

  <section class="card">
    <div class="card-head">
      <h3>Add Profile Manually</h3>
    </div>
    <div class="form-grid">
      <div class="form-field">
        <label>Name</label>
        <input id="addProfileName" type="text" placeholder="My Mac" />
      </div>
      <div class="form-inline">
        <div class="form-field">
          <label>Host</label>
          <input id="addProfileHost" type="text" placeholder="192.168.1.100" />
        </div>
        <div class="form-field">
          <label>Port</label>
          <input id="addProfilePort" type="number" min="1" max="65535" value="8081" />
        </div>
      </div>
      <div class="checkbox-row">
        <input id="addProfileTls" type="checkbox" />
        <label for="addProfileTls">TLS (wss://)</label>
      </div>
      <button id="addProfileBtn" class="btn">Add Profile</button>
    </div>
  </section>

  <section class="card">
    <div class="card-head">
      <h3>Trusted Certificates</h3>
      <span class="pill">${escapeHtml(String(trustedFingerprints.length))} trusted</span>
    </div>
    <div class="url-list">${trustedCertsHtml}</div>
    <div class="form-row">
      <input id="fingerprintInput" type="text" placeholder="SHA-256 fingerprint (hex)" />
      <button id="addFingerprintBtn" class="btn">Add</button>
    </div>
  </section>

  <script nonce="${nonce}">
    const vscode = acquireVsCodeApi();
    const allUrls = ${urlValues};

    document.getElementById('refresh')?.addEventListener('click', () => {
      vscode.postMessage({ type: 'refresh' });
    });

    document.getElementById('toggleNetworking')?.addEventListener('click', (event) => {
      const target = event.currentTarget;
      const enabled = target?.getAttribute('data-enabled') === '1';
      vscode.postMessage({ type: 'toggleNetworking', enabled: !enabled });
    });

    document.getElementById('savePort')?.addEventListener('click', () => {
      const input = document.getElementById('portInput');
      vscode.postMessage({ type: 'savePort', port: input?.value });
    });

    document.getElementById('copyAllUrls')?.addEventListener('click', () => {
      vscode.postMessage({ type: 'copyAllUrls', urls: allUrls });
    });

    document.querySelectorAll('[data-copy]').forEach((btn) => {
      btn.addEventListener('click', () => {
        vscode.postMessage({ type: 'copy', text: btn.getAttribute('data-copy') });
      });
    });

    // QR Import
    document.getElementById('importQRBtn')?.addEventListener('click', () => {
      const input = document.getElementById('qrPayloadInput');
      vscode.postMessage({ type: 'importQRPayload', payload: input?.value });
    });

    // Add Profile
    document.getElementById('addProfileBtn')?.addEventListener('click', () => {
      const name = document.getElementById('addProfileName')?.value;
      const host = document.getElementById('addProfileHost')?.value;
      const port = document.getElementById('addProfilePort')?.value;
      const tls = document.getElementById('addProfileTls')?.checked ?? false;
      vscode.postMessage({ type: 'addProfile', name, host, port: Number(port), tlsEnabled: tls });
    });

    // Profile actions (connect, set default, delete)
    document.querySelectorAll('[data-connect-profile]').forEach((btn) => {
      btn.addEventListener('click', () => {
        vscode.postMessage({ type: 'connectToProfile', profileId: btn.getAttribute('data-connect-profile') });
      });
    });

    document.querySelectorAll('[data-set-default]').forEach((btn) => {
      btn.addEventListener('click', () => {
        vscode.postMessage({ type: 'setDefaultProfile', profileId: btn.getAttribute('data-set-default') });
      });
    });

    document.querySelectorAll('[data-delete-profile]').forEach((btn) => {
      btn.addEventListener('click', () => {
        vscode.postMessage({ type: 'deleteProfile', profileId: btn.getAttribute('data-delete-profile') });
      });
    });

    // Trusted certs
    document.getElementById('addFingerprintBtn')?.addEventListener('click', () => {
      const input = document.getElementById('fingerprintInput');
      vscode.postMessage({ type: 'addTrustedFingerprint', fingerprint: input?.value });
    });

    document.querySelectorAll('[data-remove-fingerprint]').forEach((btn) => {
      btn.addEventListener('click', () => {
        vscode.postMessage({ type: 'removeTrustedFingerprint', fingerprint: btn.getAttribute('data-remove-fingerprint') });
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
