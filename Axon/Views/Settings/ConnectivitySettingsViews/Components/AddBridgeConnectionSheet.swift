//
//  AddBridgeConnectionSheet.swift
//  Axon
//
//  Create a new saved Axon Bridge connection profile.
//

import SwiftUI

struct AddBridgeConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialName: String
    let initialHost: String
    let initialPort: UInt16
    let initialTLSEnabled: Bool
    let importedPairingToken: String?
    let onSave: (_ name: String, _ host: String, _ port: UInt16, _ tlsEnabled: Bool, _ applyPairingToken: Bool) -> Void

    @State private var name: String
    @State private var host: String
    @State private var portText: String
    @State private var tlsEnabled: Bool
    @State private var applyImportedPairingToken = true
    @State private var validationError: String?

    init(
        initialName: String = "",
        initialHost: String = "",
        initialPort: UInt16 = 8082,
        initialTLSEnabled: Bool = false,
        importedPairingToken: String? = nil,
        onSave: @escaping (_ name: String, _ host: String, _ port: UInt16, _ tlsEnabled: Bool, _ applyPairingToken: Bool) -> Void
    ) {
        self.initialName = initialName
        self.initialHost = initialHost
        self.initialPort = initialPort
        self.initialTLSEnabled = initialTLSEnabled
        self.importedPairingToken = importedPairingToken
        self.onSave = onSave

        _name = State(initialValue: initialName)
        _host = State(initialValue: initialHost)
        _portText = State(initialValue: String(initialPort))
        _tlsEnabled = State(initialValue: initialTLSEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Name", text: $name)
                    TextField("Host or IP", text: $host)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        #endif

                    TextField("Port", text: $portText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif

                    Toggle("Use TLS (wss://)", isOn: $tlsEnabled)
                }

                if let importedPairingToken, !importedPairingToken.isEmpty {
                    Section("QR Import") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Pairing token found in QR payload.")
                                .font(AppTypography.bodySmall(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text(importedPairingToken)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(2)
                        }

                        Toggle("Apply pairing token to global bridge token", isOn: $applyImportedPairingToken)
                    }
                }

                if let validationError, !validationError.isEmpty {
                    Section {
                        Text(validationError)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.accentError)
                    }
                }
            }
            .navigationTitle("Add Connection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            validationError = "Connection name is required."
            return
        }

        guard !trimmedHost.isEmpty else {
            validationError = "Host is required."
            return
        }

        guard let parsedPort = Int(portText), (1...65535).contains(parsedPort), let finalPort = UInt16(exactly: parsedPort) else {
            validationError = "Port must be between 1 and 65535."
            return
        }

        validationError = nil
        onSave(trimmedName, trimmedHost, finalPort, tlsEnabled, applyImportedPairingToken)
        dismiss()
    }
}
