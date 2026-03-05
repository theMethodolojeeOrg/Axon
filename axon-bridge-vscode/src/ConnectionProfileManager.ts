import * as vscode from "vscode";
import * as crypto from "crypto";

/**
 * A saved connection profile for connecting to an Axon host.
 */
export interface ConnectionProfile {
  id: string;
  name: string;
  host: string;
  port: number;
  tlsEnabled: boolean;
  createdAt: string;
  lastConnectedAt?: string;
}

/**
 * Result of parsing a QR/ws:// payload.
 */
export interface QRParseResult {
  host: string;
  port: number;
  tlsEnabled: boolean;
  pairingToken?: string;
}

/**
 * Manages connection profiles stored in VS Code settings.
 * Mirrors the profile management found in the iOS BridgeSettingsStorage.
 */
export class ConnectionProfileManager {
  private static readonly configSection = "axonBridge";

  static getProfiles(): ConnectionProfile[] {
    const config = vscode.workspace.getConfiguration(this.configSection);
    return config.get<ConnectionProfile[]>("connectionProfiles", []);
  }

  static addProfile(
    name: string,
    host: string,
    port: number,
    tlsEnabled: boolean
  ): ConnectionProfile {
    const profiles = this.getProfiles();
    const profile: ConnectionProfile = {
      id: crypto.randomUUID(),
      name: name.trim(),
      host: host.trim(),
      port,
      tlsEnabled,
      createdAt: new Date().toISOString(),
    };
    profiles.push(profile);
    this.saveProfiles(profiles);
    return profile;
  }

  static updateProfile(
    id: string,
    updates: Partial<Omit<ConnectionProfile, "id" | "createdAt">>
  ): boolean {
    const profiles = this.getProfiles();
    const index = profiles.findIndex((p) => p.id === id);
    if (index === -1) return false;

    if (updates.name !== undefined)
      profiles[index].name = updates.name.trim();
    if (updates.host !== undefined)
      profiles[index].host = updates.host.trim();
    if (updates.port !== undefined) profiles[index].port = updates.port;
    if (updates.tlsEnabled !== undefined)
      profiles[index].tlsEnabled = updates.tlsEnabled;
    if (updates.lastConnectedAt !== undefined)
      profiles[index].lastConnectedAt = updates.lastConnectedAt;

    this.saveProfiles(profiles);
    return true;
  }

  static deleteProfile(id: string): boolean {
    const profiles = this.getProfiles();
    const filtered = profiles.filter((p) => p.id !== id);
    if (filtered.length === profiles.length) return false;

    this.saveProfiles(filtered);

    // Clear default if it was the deleted profile
    const defaultId = this.getDefaultProfileId();
    if (defaultId === id) {
      this.setDefaultProfile(null);
    }

    return true;
  }

  static getDefaultProfileId(): string {
    const config = vscode.workspace.getConfiguration(this.configSection);
    return config.get<string>("defaultProfileId", "");
  }

  static getDefaultProfile(): ConnectionProfile | undefined {
    const id = this.getDefaultProfileId();
    if (!id) return undefined;
    return this.getProfiles().find((p) => p.id === id);
  }

  static setDefaultProfile(id: string | null): void {
    const config = vscode.workspace.getConfiguration(this.configSection);
    config.update(
      "defaultProfileId",
      id ?? "",
      vscode.ConfigurationTarget.Global
    );
  }

  static markConnected(id: string): void {
    this.updateProfile(id, {
      lastConnectedAt: new Date().toISOString(),
    });
  }

  /**
   * Parse a ws:// or wss:// QR payload into connection parameters.
   * Format: ws://host:port or wss://host:port?pairingToken=TOKEN
   */
  static parseQRPayload(payload: string): QRParseResult | null {
    const trimmed = payload.trim();
    if (!trimmed) return null;

    let url: URL;
    try {
      url = new URL(trimmed);
    } catch {
      return null;
    }

    const scheme = url.protocol.replace(":", "").toLowerCase();
    if (scheme !== "ws" && scheme !== "wss") return null;

    const host = url.hostname;
    if (!host) return null;

    const port = url.port ? parseInt(url.port, 10) : scheme === "wss" ? 443 : 80;
    if (isNaN(port) || port < 1 || port > 65535) return null;

    const pairingToken = url.searchParams.get("pairingToken") || undefined;

    return {
      host,
      port,
      tlsEnabled: scheme === "wss",
      pairingToken: pairingToken?.trim() || undefined,
    };
  }

  /**
   * Parse a QR payload and create a profile from it in one step.
   */
  static importFromQRPayload(
    payload: string,
    name?: string
  ): ConnectionProfile | null {
    const parsed = this.parseQRPayload(payload);
    if (!parsed) return null;

    const profileName = name?.trim() || `Bridge ${parsed.host}`;
    return this.addProfile(
      profileName,
      parsed.host,
      parsed.port,
      parsed.tlsEnabled
    );
  }

  private static saveProfiles(profiles: ConnectionProfile[]): void {
    const config = vscode.workspace.getConfiguration(this.configSection);
    config.update(
      "connectionProfiles",
      profiles,
      vscode.ConfigurationTarget.Global
    );
  }
}
