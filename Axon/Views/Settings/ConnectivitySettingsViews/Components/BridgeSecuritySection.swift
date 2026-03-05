//
//  BridgeSecuritySection.swift
//  Axon
//
//  Security settings for the Bridge: pairing token, TLS, trusted certificate fingerprints.
//

import SwiftUI

struct BridgeSecuritySection: View {
    @ObservedObject var bridgeSettings: BridgeSettingsStorage
    @ObservedObject var bridgeServer: BridgeServer

    @State private var pairingTokenInput: String = ""
    @State private var fingerprintInput: String = ""
    @State private var fingerprintError: String?
    @State private var showingAddFingerprint = false

    var body: some View {
        SettingsSection(title: "Security") {
            VStack(spacing: 12) {
                pairingTokenRow
                tlsToggleRow
                tlsFingerprintDisplay
                trustedFingerprintsRow
            }
        }
    }

    // MARK: - Pairing Token

    private var pairingTokenRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pairing Token")
                .font(AppTypography.bodySmall(.medium))
                .foregroundColor(AppColors.textPrimary)

            Text("Require this token for all connections. Leave empty to allow any.")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: 8) {
                SecureField("Optional token", text: $pairingTokenInput)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .onAppear {
                        pairingTokenInput = bridgeSettings.settings.requiredPairingToken
                    }

                Button("Save") {
                    bridgeSettings.setRequiredPairingToken(pairingTokenInput)
                }
                .buttonStyle(.bordered)
                .disabled(pairingTokenInput.trimmingCharacters(in: .whitespacesAndNewlines) == bridgeSettings.settings.requiredPairingToken)
            }
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }

    // MARK: - TLS Toggle

    private var tlsToggleRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Enable TLS (wss://)")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text("Encrypt connections with TLS.")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { bridgeSettings.settings.tlsEnabled },
                    set: { bridgeSettings.setTLSEnabled($0) }
                )
            )
            .labelsHidden()
            .tint(AppColors.signalMercury)
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }

    // MARK: - TLS Fingerprint Display (Host Mode)

    @ViewBuilder
    private var tlsFingerprintDisplay: some View {
        if bridgeSettings.settings.mode == .local,
           bridgeSettings.settings.tlsEnabled,
           bridgeServer.isRunning,
           let fingerprint = bridgeServer.certificateFingerprint {
            VStack(alignment: .leading, spacing: 6) {
                Text("Server Certificate Fingerprint")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)

                Text(BridgeTLSConfig.formatFingerprint(fingerprint))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(3)

                Button {
                    let formatted = BridgeTLSConfig.formatFingerprint(fingerprint)
                    #if os(iOS)
                    UIPasteboard.general.string = formatted
                    #elseif os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(formatted, forType: .string)
                    #endif
                } label: {
                    Label("Copy Fingerprint", systemImage: "doc.on.doc")
                }
                .font(AppTypography.labelSmall())
                .buttonStyle(.borderless)
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
    }

    // MARK: - Trusted Fingerprints (Client Mode)

    @ViewBuilder
    private var trustedFingerprintsRow: some View {
        if bridgeSettings.settings.mode == .remote {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Trusted Certificate Fingerprints")
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Button {
                        showingAddFingerprint = true
                        fingerprintInput = ""
                        fingerprintError = nil
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }

                if bridgeSettings.settings.trustedCertFingerprints.isEmpty {
                    Text("No trusted fingerprints. All certificates will be accepted.")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                } else {
                    ForEach(bridgeSettings.settings.trustedCertFingerprints, id: \.self) { fp in
                        HStack {
                            Text(BridgeTLSConfig.formatFingerprint(fp))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(1)

                            Spacer()

                            Button(role: .destructive) {
                                bridgeSettings.removeTrustedCertFingerprint(fp)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                if showingAddFingerprint {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("SHA-256 fingerprint (hex)", text: $fingerprintInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif

                        if let error = fingerprintError {
                            Text(error)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.accentError)
                        }

                        HStack(spacing: 8) {
                            Button("Add") {
                                let normalized = BridgeTLSConfig.normalizeFingerprint(fingerprintInput)
                                if BridgeTLSConfig.isValidFingerprint(normalized) {
                                    bridgeSettings.addTrustedCertFingerprint(normalized)
                                    showingAddFingerprint = false
                                    fingerprintInput = ""
                                    fingerprintError = nil
                                } else {
                                    fingerprintError = "Invalid fingerprint. Expected 64 hex characters (SHA-256)."
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Cancel") {
                                showingAddFingerprint = false
                                fingerprintInput = ""
                                fingerprintError = nil
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
    }
}
