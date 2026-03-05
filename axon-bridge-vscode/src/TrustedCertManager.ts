import * as vscode from "vscode";

/**
 * Manages trusted TLS certificate fingerprints stored in VS Code settings.
 * Mirrors the iOS BridgeTLSConfig fingerprint management.
 */
export class TrustedCertManager {
  private static readonly configSection = "axonBridge";

  static getTrustedFingerprints(): string[] {
    const config = vscode.workspace.getConfiguration(this.configSection);
    return config.get<string[]>("trustedCertFingerprints", []);
  }

  static addTrustedFingerprint(fingerprint: string): boolean {
    const normalized = this.normalizeFingerprint(fingerprint);
    if (!this.isValidFingerprint(normalized)) return false;

    const fps = this.getTrustedFingerprints();
    if (fps.some((fp) => this.normalizeFingerprint(fp) === normalized)) {
      return false; // Already trusted
    }

    fps.push(normalized);
    this.saveFingerprints(fps);
    return true;
  }

  static removeTrustedFingerprint(fingerprint: string): boolean {
    const normalized = this.normalizeFingerprint(fingerprint);
    const fps = this.getTrustedFingerprints();
    const filtered = fps.filter(
      (fp) => this.normalizeFingerprint(fp) !== normalized
    );
    if (filtered.length === fps.length) return false;

    this.saveFingerprints(filtered);
    return true;
  }

  static isTrusted(fingerprint: string): boolean {
    const normalized = this.normalizeFingerprint(fingerprint);
    return this.getTrustedFingerprints().some(
      (fp) => this.normalizeFingerprint(fp) === normalized
    );
  }

  /**
   * Normalize a fingerprint to lowercase hex without separators.
   * Accepts AA:BB:CC, AABBCC, aa:bb:cc formats.
   */
  static normalizeFingerprint(input: string): string {
    return input
      .toLowerCase()
      .replace(/[:\s]/g, "")
      .trim();
  }

  /**
   * Format a fingerprint for display with colon separators.
   */
  static formatFingerprint(fingerprint: string): string {
    const normalized = this.normalizeFingerprint(fingerprint).toUpperCase();
    return normalized.match(/.{1,2}/g)?.join(":") ?? normalized;
  }

  /**
   * Validate that a fingerprint string is a valid SHA-256 hex digest.
   */
  static isValidFingerprint(fingerprint: string): boolean {
    const normalized = this.normalizeFingerprint(fingerprint);
    return /^[0-9a-f]{64}$/.test(normalized);
  }

  private static saveFingerprints(fps: string[]): void {
    const config = vscode.workspace.getConfiguration(this.configSection);
    config.update(
      "trustedCertFingerprints",
      fps,
      vscode.ConfigurationTarget.Global
    );
  }
}
