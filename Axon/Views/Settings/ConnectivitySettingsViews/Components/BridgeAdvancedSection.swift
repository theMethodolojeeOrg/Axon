//
//  BridgeAdvancedSection.swift
//  Axon
//
//  Advanced Bridge settings: multi-session, file access controls, blocked patterns.
//

import SwiftUI

struct BridgeAdvancedSection: View {
    @ObservedObject var bridgeSettings: BridgeSettingsStorage

    @State private var maxFileSizeText: String = ""
    @State private var terminalTimeoutText: String = ""
    @State private var newPatternInput: String = ""
    @State private var showingAddPattern = false

    var body: some View {
        SettingsSection(title: "Advanced") {
            VStack(spacing: 12) {
                multiSessionToggle
                autoStartToggle
                autoApproveReadsToggle
                maxFileSizeRow
                terminalTimeoutRow
                blockedPatternsRow
            }
        }
    }

    // MARK: - Multi-Session

    private var multiSessionToggle: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Allow multiple sessions")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text("Let multiple VS Code workspaces connect simultaneously.")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { bridgeSettings.settings.allowMultipleSessions },
                    set: { bridgeSettings.setAllowMultipleSessions($0) }
                )
            )
            .labelsHidden()
            .tint(AppColors.signalMercury)
        }
        .padding()
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }

    // MARK: - Auto-Start

    private var autoStartToggle: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-start on launch")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text("Automatically start the bridge when the app opens.")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { bridgeSettings.settings.autoStart },
                    set: { bridgeSettings.setAutoStart($0) }
                )
            )
            .labelsHidden()
            .tint(AppColors.signalMercury)
        }
        .padding()
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }

    // MARK: - Auto-Approve Reads

    private var autoApproveReadsToggle: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-approve file reads")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text("Skip confirmation for file read operations.")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { bridgeSettings.settings.autoApproveReads },
                    set: { bridgeSettings.setAutoApproveReads($0) }
                )
            )
            .labelsHidden()
            .tint(AppColors.signalMercury)
        }
        .padding()
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }

    // MARK: - Max File Size

    private var maxFileSizeRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Max file size")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text("Maximum file size for bridge file operations.")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            TextField("10", text: $maxFileSizeText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onAppear {
                    maxFileSizeText = String(bridgeSettings.settings.maxFileSize / (1024 * 1024))
                }
                .onChange(of: maxFileSizeText) { newValue in
                    if let mb = Int(newValue), mb > 0 {
                        bridgeSettings.setMaxFileSize(mb * 1024 * 1024)
                    }
                }

            Text("MB")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding()
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }

    // MARK: - Terminal Timeout

    private var terminalTimeoutRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Terminal timeout")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text("Max seconds for terminal commands.")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            TextField("60", text: $terminalTimeoutText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onAppear {
                    terminalTimeoutText = String(bridgeSettings.settings.terminalTimeout)
                }
                .onChange(of: terminalTimeoutText) { newValue in
                    if let seconds = Int(newValue), seconds > 0 {
                        bridgeSettings.setTerminalTimeout(seconds)
                    }
                }

            Text("sec")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding()
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }

    // MARK: - Blocked Patterns

    private var blockedPatternsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Blocked File Patterns")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button {
                    showingAddPattern = true
                    newPatternInput = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            }

            Text("Files matching these glob patterns are blocked from bridge access.")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)

            ForEach(bridgeSettings.settings.blockedPatterns, id: \.self) { pattern in
                HStack {
                    Text(pattern)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(AppColors.textSecondary)

                    Spacer()

                    Button(role: .destructive) {
                        var patterns = bridgeSettings.settings.blockedPatterns
                        patterns.removeAll { $0 == pattern }
                        bridgeSettings.setBlockedPatterns(patterns)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                }
            }

            if showingAddPattern {
                HStack(spacing: 8) {
                    TextField("**/*.env", text: $newPatternInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif

                    Button("Add") {
                        let trimmed = newPatternInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        var patterns = bridgeSettings.settings.blockedPatterns
                        if !patterns.contains(trimmed) {
                            patterns.append(trimmed)
                            bridgeSettings.setBlockedPatterns(patterns)
                        }
                        showingAddPattern = false
                        newPatternInput = ""
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Cancel") {
                        showingAddPattern = false
                        newPatternInput = ""
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }
}
