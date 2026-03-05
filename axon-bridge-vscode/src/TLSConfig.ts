/**
 * TLSConfig.ts
 *
 * TLS configuration helpers for secure WebSocket connections.
 * Auto-generates self-signed certificates on first use and caches them to disk.
 */

import * as crypto from 'crypto';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';
import { generate as selfsignedGenerate } from 'selfsigned';

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
 */
export function calculateFingerprint(certPem: string): string {
    const lines = certPem.split('\n');
    const base64 = lines
        .filter(line => !line.startsWith('-----'))
        .join('');
    const der = Buffer.from(base64, 'base64');

    const hash = crypto.createHash('sha256');
    hash.update(der);
    return hash.digest('hex');
}

/**
 * Format fingerprint for display (with colons)
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

// MARK: - Certificate Storage

/**
 * Get the directory where certificates are stored
 */
export function getCertificatePath(): string {
    const globalStoragePath = vscode.extensions.getExtension('axon.axon-bridge')?.extensionPath;
    if (globalStoragePath) {
        return path.join(globalStoragePath, 'certs');
    }
    return path.join(os.tmpdir(), 'axon-bridge-certs');
}

/**
 * Check if a certificate already exists on disk
 */
export function certificateExists(): boolean {
    const certDir = getCertificatePath();
    const certPath = path.join(certDir, 'server.crt');
    const keyPath = path.join(certDir, 'server.key');
    return fs.existsSync(certPath) && fs.existsSync(keyPath);
}

/**
 * Load an existing certificate from disk
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

// MARK: - Certificate Generation

/**
 * Generate a self-signed certificate and save it to disk.
 * Uses the `selfsigned` package for in-process generation (no openssl needed).
 * The cert is valid for 365 days and includes SANs for localhost + LAN IPs.
 */
export async function generateCertificate(): Promise<TLSCertificate> {
    console.log('[TLSConfig] Generating self-signed certificate...');

    // Collect Subject Alternative Names: localhost + all LAN IPv4 addresses
    const altNames: Array<{ type: 2; value: string } | { type: 7; ip: string }> = [
        { type: 2, value: 'localhost' },           // DNS
        { type: 7, ip: '127.0.0.1' },              // IP
    ];

    const interfaces = os.networkInterfaces();
    for (const entries of Object.values(interfaces)) {
        for (const iface of entries ?? []) {
            if (iface.family === 'IPv4' && !iface.internal) {
                altNames.push({ type: 7, ip: iface.address });
            }
        }
    }

    const now = new Date();
    const notAfter = new Date(now);
    notAfter.setFullYear(notAfter.getFullYear() + 1);

    const attrs = [{ name: 'commonName', value: 'Axon Bridge' }];
    const pems = await selfsignedGenerate(attrs, {
        keySize: 2048,
        notBeforeDate: now,
        notAfterDate: notAfter,
        algorithm: 'sha256',
        extensions: [
            { name: 'subjectAltName', altNames },
        ],
    });

    const fingerprint = calculateFingerprint(pems.cert);

    // Persist to disk so we reuse the same cert across restarts
    const certDir = getCertificatePath();
    fs.mkdirSync(certDir, { recursive: true });
    fs.writeFileSync(path.join(certDir, 'server.crt'), pems.cert, 'utf-8');
    fs.writeFileSync(path.join(certDir, 'server.key'), pems.private, 'utf-8');

    console.log(`[TLSConfig] Certificate generated. Fingerprint: ${formatFingerprint(fingerprint)}`);

    return { cert: pems.cert, key: pems.private, fingerprint };
}

/**
 * Load an existing certificate or generate one if none exists.
 */
export async function ensureCertificate(): Promise<TLSCertificate> {
    const existing = loadCertificate();
    if (existing) {
        console.log(`[TLSConfig] Using existing certificate. Fingerprint: ${formatFingerprint(existing.fingerprint)}`);
        return existing;
    }
    return await generateCertificate();
}

/**
 * Get TLS options for https.createServer()
 */
export async function getTLSOptions(): Promise<TLSOptions> {
    const cert = await ensureCertificate();
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
        vscode.window.showWarningMessage('No TLS certificate found. Enable TLS and start the server to auto-generate one.');
        return;
    }

    const formatted = formatFingerprint(cert.fingerprint);
    vscode.window.showInformationMessage(
        `Certificate Fingerprint (SHA-256):\n\n${formatted}\n\nCopy this to Axon to trust this server.`,
        { modal: true }
    );
}
