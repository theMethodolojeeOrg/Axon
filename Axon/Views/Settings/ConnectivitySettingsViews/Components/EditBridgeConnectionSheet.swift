//
//  EditBridgeConnectionSheet.swift
//  Axon
//
//  Edit an existing Axon Bridge connection profile.
//

import SwiftUI

struct EditBridgeConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let profile: BridgeConnectionProfile
    let onSave: (BridgeConnectionProfile) -> Void

    @State private var name: String
    @State private var host: String
    @State private var portText: String
    @State private var tlsEnabled: Bool
    @State private var validationError: String?

    init(profile: BridgeConnectionProfile, onSave: @escaping (BridgeConnectionProfile) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _name = State(initialValue: profile.name)
        _host = State(initialValue: profile.host)
        _portText = State(initialValue: String(profile.port))
        _tlsEnabled = State(initialValue: profile.tlsEnabled)
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

                if let validationError, !validationError.isEmpty {
                    Section {
                        Text(validationError)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.accentError)
                    }
                }
            }
            .navigationTitle("Edit Connection")
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
        let updated = BridgeConnectionProfile(
            id: profile.id,
            name: trimmedName,
            host: trimmedHost,
            port: finalPort,
            tlsEnabled: tlsEnabled,
            createdAt: profile.createdAt,
            lastConnectedAt: profile.lastConnectedAt
        )
        onSave(updated)
        dismiss()
    }
}
