/**
 * TLSConfig.ts
 *
 * TLS configuration helpers for secure WebSocket connections.
 * Supports self-signed certificate generation and fingerprint display.
 */

import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';

// MARK: - Types

export interface TLSCertificate {
    cert: string;       // PEM-encoded certificate
    key: string;        // PEM-encoded private key
    fingerprint: string; // SHA-256 fingerprint (hex)
}

export interface TLSOptions {
    cert: Buffer;
    key: Buffer;
}

// MARK: - Certificate Utilities

/**
 * Calculate SHA-256 fingerprint of a certificate
 * @param certPem PEM-encoded certificate
 * @returns Hex string fingerprint
 */
export function calculateFingerprint(certPem: string): string {
    // Extract DER from PEM
    const lines = certPem.split('\n');
    const base64 = lines
        .filter(line => !line.startsWith('-----'))
        .join('');
    const der = Buffer.from(base64, 'base64');

    // Calculate SHA-256 hash
    const hash = crypto.createHash('sha256');
    hash.update(der);
    return hash.digest('hex');
}

/**
 * Format fingerprint for display (with colons)
 * @param fingerprint Raw hex fingerprint
 * @returns Formatted like "AA:BB:CC:DD:..."
 */
export function formatFingerprint(fingerprint: string): string {
    const upper = fingerprint.toUpperCase();
    const pairs: string[] = [];
    for (let i = 0; i < upper.length; i += 2) {
        pairs.push(upper.substring(i, i + 2));
    }
    return pairs.join(':');
}

/**
 * Normalize a fingerprint (remove colons/spaces, lowercase)
 */
export function normalizeFingerprint(input: string): string {
    return input
        .toLowerCase()
        .replace(/:/g, '')
        .replace(/ /g, '')
        .trim();
}

/**
 * Validate fingerprint format (64 hex chars for SHA-256)
 */
export function isValidFingerprint(fingerprint: string): boolean {
    const normalized = normalizeFingerprint(fingerprint);
    if (normalized.length !== 64) return false;
    return /^[0-9a-f]{64}$/.test(normalized);
}

// MARK: - Certificate Generation

/**
 * Get the path where certificates should be stored
 */
export function getCertificatePath(): string {
    const globalStoragePath = vscode.extensions.getExtension('axon.axon-bridge')?.extensionPath;
    if (globalStoragePath) {
        return path.join(globalStoragePath, 'certs');
    }
    // Fallback to temp directory
    return path.join(require('os').tmpdir(), 'axon-bridge-certs');
}

/**
 * Check if a certificate exists
 */
export function certificateExists(): boolean {
    const certDir = getCertificatePath();
    const certPath = path.join(certDir, 'server.crt');
    const keyPath = path.join(certDir, 'server.key');
    return fs.existsSync(certPath) && fs.existsSync(keyPath);
}

/**
 * Load existing certificate
 */
export function loadCertificate(): TLSCertificate | null {
    try {
        const certDir = getCertificatePath();
        const certPath = path.join(certDir, 'server.crt');
        const keyPath = path.join(certDir, 'server.key');

        if (!fs.existsSync(certPath) || !fs.existsSync(keyPath)) {
            return null;
        }

        const cert = fs.readFileSync(certPath, 'utf-8');
        const key = fs.readFileSync(keyPath, 'utf-8');
        const fingerprint = calculateFingerprint(cert);

        return { cert, key, fingerprint };
    } catch (error) {
        console.error('[TLSConfig] Failed to load certificate:', error);
        return null;
    }
}

/**
 * Generate a self-signed certificate
 * Note: This requires the 'selfsigned' package or Node.js crypto
 * For now, we'll provide instructions for manual generation
 */
export async function generateCertificate(): Promise<TLSCertificate | null> {
    // Self-signed certificate generation requires additional dependencies
    // or native Node.js crypto which doesn't have a simple API for this.
    //
    // For MVP, we'll show instructions for manual certificate generation.
    //
    // In a full implementation, we could:
    // 1. Add 'selfsigned' or 'node-forge' as a dependency
    // 2. Use OpenSSL via child_process
    // 3. Use the Web Crypto API with a polyfill

    const message = `To enable TLS for Remote Mode, generate a self-signed certificate:

1. Open a terminal
2. Navigate to: ${getCertificatePath()}
3. Run: openssl req -x509 -newkey rsa:4096 -keyout server.key -out server.crt -days 365 -nodes -subj "/CN=localhost"
4. Restart VS Code

The certificate fingerprint will be displayed when the server starts.
Copy it to Axon to enable secure connections.`;

    vscode.window.showInformationMessage(message, { modal: true });

    return null;
}

/**
 * Get TLS options for the HTTPS server
 */
export function getTLSOptions(): TLSOptions | null {
    const cert = loadCertificate();
    if (!cert) return null;

    return {
        cert: Buffer.from(cert.cert),
        key: Buffer.from(cert.key),
    };
}

/**
 * Display certificate fingerprint to user
 */
export function showCertificateFingerprint(): void {
    const cert = loadCertificate();
    if (!cert) {
        vscode.window.showWarningMessage('No TLS certificate found. Generate one first.');
        return;
    }

    const formatted = formatFingerprint(cert.fingerprint);
    vscode.window.showInformationMessage(
        `Certificate Fingerprint (SHA-256):\n\n${formatted}\n\nCopy this to Axon to trust this server.`,
        { modal: true }
    );
}
