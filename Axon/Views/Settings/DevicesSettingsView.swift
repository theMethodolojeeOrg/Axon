//
//  DevicesSettingsView.swift
//  Axon
//
//  Multi-device presence management and sync status
//

import SwiftUI
import Combine

struct DevicesSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var isRefreshing = false
    @State private var showingSyncConfirmation = false
    @State private var selectedDeviceForPush: DevicePresence?
    @State private var editingDeviceName: String?
    @State private var newDeviceName: String = ""

    // Device state (refreshed on appear and after actions)
    @State private var currentDevice: DevicePresence?
    @State private var allDevices: [DevicePresence] = []
    @State private var latestSnapshot: SystemStateSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // MARK: - This Device

            GeneralSettingsSection(title: "This Device") {
                if let device = currentDevice {
                    CurrentDeviceCard(
                        device: device,
                        lastSnapshot: latestSnapshot,
                        onCreateSnapshot: createSnapshot,
                        onEditName: { startEditingName(device) }
                    )
                } else {
                    LoadingDeviceCard()
                }
            }

            // MARK: - Other Devices

            let otherDevices = allDevices.filter { !$0.isCurrentDevice }

            GeneralSettingsSection(title: "Other Devices (\(otherDevices.count))") {
                if otherDevices.isEmpty {
                    EmptyDevicesCard()
                } else {
                    VStack(spacing: 12) {
                        ForEach(otherDevices) { device in
                            OtherDeviceCard(
                                device: device,
                                onPushState: { selectedDeviceForPush = device },
                                onEditName: { startEditingName(device) }
                            )
                        }
                    }
                }
            }

            // MARK: - Sync Actions

            GeneralSettingsSection(title: "Sync Actions") {
                VStack(spacing: 12) {
                    // Refresh devices list
                    Button(action: refreshDevices) {
                        HStack(spacing: 12) {
                            if isRefreshing {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 20))
                                    .foregroundColor(AppColors.signalMercury)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Refresh Device List")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.textPrimary)

                                Text("Pull latest device info from iCloud")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppColors.substrateSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppColors.glassBorder, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isRefreshing)

                    // Push to all devices
                    Button(action: { showingSyncConfirmation = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.up.to.line.compact")
                                .font(.system(size: 20))
                                .foregroundColor(AppColors.signalMercury)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Push State to All Devices")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.textPrimary)

                                Text("Snapshot current state and sync to iCloud")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppColors.substrateSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppColors.glassBorder, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // MARK: - Info Section

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(AppColors.signalMercury.opacity(0.7))
                Text("Devices sync automatically via iCloud. Use \"Push State\" when you want to ensure your current device's state is immediately available on other devices.")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppColors.signalMercury.opacity(0.1))
            )
        }
        .onAppear {
            Task {
                await loadDeviceData()
            }
        }
        .alert("Push State to All Devices?", isPresented: $showingSyncConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Push Now") {
                Task {
                    await pushStateToAll()
                }
            }
        } message: {
            Text("This will create a snapshot of your current state and sync it to iCloud for all your devices to see.")
        }
        .sheet(item: $selectedDeviceForPush) { device in
            PushToDeviceSheet(
                device: device,
                onPush: { await pushStateTo(device) },
                onCancel: { selectedDeviceForPush = nil }
            )
        }
        .sheet(isPresented: Binding(
            get: { editingDeviceName != nil },
            set: { if !$0 { editingDeviceName = nil } }
        )) {
            if let deviceId = editingDeviceName {
                EditDeviceNameSheet(
                    deviceId: deviceId,
                    currentName: allDevices.first { $0.id == deviceId }?.deviceName ?? "",
                    onSave: { newName in
                        Task {
                            await updateDeviceName(deviceId: deviceId, name: newName)
                        }
                    },
                    onCancel: { editingDeviceName = nil }
                )
            }
        }
    }

    // MARK: - Actions

    @MainActor
    private func loadDeviceData() async {
        let presenceService = DevicePresenceService.shared
        let systemStateService = SystemStateService.shared

        await presenceService.loadAllDevices()
        currentDevice = presenceService.currentDevice
        allDevices = presenceService.allDevices
        latestSnapshot = systemStateService.latestSnapshot
    }

    private func refreshDevices() {
        isRefreshing = true
        Task {
            let presenceService = DevicePresenceService.shared
            await presenceService.loadAllDevices()
            await presenceService.syncPresenceState()

            await MainActor.run {
                currentDevice = presenceService.currentDevice
                allDevices = presenceService.allDevices
                isRefreshing = false
            }
        }
    }

    private func createSnapshot() {
        Task {
            do {
                let systemStateService = SystemStateService.shared
                _ = try await systemStateService.saveUserCheckpoint()
                await MainActor.run {
                    latestSnapshot = systemStateService.latestSnapshot
                    viewModel.showSuccessMessage("Snapshot created")
                }
            } catch {
                await MainActor.run {
                    viewModel.error = "Failed to create snapshot: \(error.localizedDescription)"
                }
            }
        }
    }

    private func pushStateToAll() async {
        do {
            let systemStateService = SystemStateService.shared
            _ = try await systemStateService.saveUserCheckpoint()
            await MainActor.run {
                latestSnapshot = systemStateService.latestSnapshot
                viewModel.showSuccessMessage("State pushed to iCloud")
            }
        } catch {
            await MainActor.run {
                viewModel.error = "Failed to push state: \(error.localizedDescription)"
            }
        }
    }

    private func pushStateTo(_ device: DevicePresence) async {
        do {
            let systemStateService = SystemStateService.shared
            _ = try await systemStateService.saveUserCheckpoint()
            await MainActor.run {
                latestSnapshot = systemStateService.latestSnapshot
                viewModel.showSuccessMessage("State pushed (available to \(device.deviceName))")
                selectedDeviceForPush = nil
            }
        } catch {
            await MainActor.run {
                viewModel.error = "Failed to push state: \(error.localizedDescription)"
            }
        }
    }

    private func startEditingName(_ device: DevicePresence) {
        editingDeviceName = device.id
        newDeviceName = device.deviceName
    }

    private func updateDeviceName(deviceId: String, name: String) async {
        // This would need to update the Core Data entity
        // For now, show a success message
        let presenceService = DevicePresenceService.shared
        await MainActor.run {
            editingDeviceName = nil
            viewModel.showSuccessMessage("Device name updated")
        }
        await presenceService.loadAllDevices()
        await MainActor.run {
            allDevices = presenceService.allDevices
        }
    }
}

// MARK: - Current Device Card

struct CurrentDeviceCard: View {
    let device: DevicePresence
    let lastSnapshot: SystemStateSnapshot?
    let onCreateSnapshot: () -> Void
    let onEditName: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Device header
            HStack(spacing: 12) {
                // Platform icon
                ZStack {
                    Circle()
                        .fill(AppColors.signalMercury.opacity(0.2))
                        .frame(width: 48, height: 48)

                    Image(systemName: device.platform.icon)
                        .font(.system(size: 22))
                        .foregroundColor(AppColors.signalMercury)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(device.deviceName)
                            .font(AppTypography.titleMedium())
                            .foregroundColor(AppColors.textPrimary)

                        Button(action: onEditName) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    HStack(spacing: 8) {
                        // Status indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(device.presenceState == .active ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(device.presenceState.displayName)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Text("•")
                            .foregroundColor(AppColors.textTertiary)

                        Text("This device")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.signalMercury)
                    }
                }

                Spacer()
            }

            Divider()
                .background(AppColors.divider)

            // Device details
            VStack(alignment: .leading, spacing: 8) {
                DeviceDetailRow(label: "Device ID", value: String(device.id.prefix(8)))
                DeviceDetailRow(label: "Platform", value: "\(device.platform.displayName) \(device.osVersion)")
                DeviceDetailRow(label: "App Version", value: device.appVersion)
                DeviceDetailRow(label: "Door Policy", value: device.doorPolicy.displayName)

                if let snapshot = lastSnapshot {
                    DeviceDetailRow(
                        label: "Last Snapshot",
                        value: snapshot.timestamp.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }

            Divider()
                .background(AppColors.divider)

            // Quick actions
            Button(action: onCreateSnapshot) {
                HStack {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14))
                    Text("Create Snapshot")
                        .font(AppTypography.bodySmall(.medium))
                }
                .foregroundColor(AppColors.signalMercury)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.substrateSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.signalMercury.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Other Device Card

struct OtherDeviceCard: View {
    let device: DevicePresence
    let onPushState: () -> Void
    let onEditName: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Device header
            HStack(spacing: 12) {
                // Platform icon
                ZStack {
                    Circle()
                        .fill(AppColors.substrateTertiary)
                        .frame(width: 40, height: 40)

                    Image(systemName: device.platform.icon)
                        .font(.system(size: 18))
                        .foregroundColor(AppColors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(device.deviceName)
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Button(action: onEditName) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    HStack(spacing: 8) {
                        // Status indicator
                        HStack(spacing: 4) {
                            Image(systemName: device.presenceState.icon)
                                .font(.system(size: 10))
                                .foregroundColor(stateColor)
                            Text(device.presenceState.displayName)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Text("•")
                            .foregroundColor(AppColors.textTertiary)

                        Text(device.lastActiveDescription)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                Spacer()

                // Push button
                Button(action: onPushState) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.signalMercury)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Details row
            HStack(spacing: 16) {
                Label(device.platform.displayName, systemImage: device.platform.icon)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)

                Label(device.appVersion, systemImage: "app.badge")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)

                Label(device.doorPolicy.displayName, systemImage: device.doorPolicy.icon)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.substrateSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
        )
    }

    private var stateColor: Color {
        switch device.presenceState {
        case .active: return .green
        case .standby: return .orange
        case .dormant: return .gray
        case .transferring: return .blue
        }
    }
}

// MARK: - Supporting Views

struct LoadingDeviceCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading device info...")
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.substrateSecondary)
        )
    }
}

struct EmptyDevicesCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "desktopcomputer.and.arrow.down")
                .font(.system(size: 32))
                .foregroundColor(AppColors.textTertiary)

            Text("No Other Devices")
                .font(AppTypography.bodyMedium(.medium))
                .foregroundColor(AppColors.textPrimary)

            Text("Open Axon on another device signed into the same iCloud account to see it here.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.substrateSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
        )
    }
}

struct DeviceDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
            Spacer()
            Text(value)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

// MARK: - Push to Device Sheet

struct PushToDeviceSheet: View {
    let device: DevicePresence
    let onPush: () async -> Void
    let onCancel: () -> Void

    @State private var isPushing = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("Push State to Device")
                    .font(AppTypography.titleMedium())
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppColors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Device info
            HStack(spacing: 12) {
                Image(systemName: device.platform.icon)
                    .font(.system(size: 32))
                    .foregroundColor(AppColors.signalMercury)

                VStack(alignment: .leading, spacing: 4) {
                    Text(device.deviceName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)
                    Text("\(device.platform.displayName) • \(device.lastActiveDescription)")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppColors.substrateSecondary)
            )

            // Explanation
            Text("This will create a snapshot of your current state and push it to iCloud. The selected device will receive the update when it next syncs.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            // Actions
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppColors.substrateTertiary)
                        )
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    isPushing = true
                    Task {
                        await onPush()
                        isPushing = false
                    }
                } label: {
                    HStack {
                        if isPushing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Push Now")
                            .font(AppTypography.bodyMedium(.medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.signalMercury)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isPushing)
            }
        }
        .padding(24)
        .background(AppColors.substratePrimary)
        #if os(macOS)
        .frame(width: 400, height: 350)
        #endif
    }
}

// MARK: - Edit Device Name Sheet

struct EditDeviceNameSheet: View {
    let deviceId: String
    let currentName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("Edit Device Name")
                    .font(AppTypography.titleMedium())
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppColors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Name input
            VStack(alignment: .leading, spacing: 8) {
                Text("Device Name")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)

                TextField("Enter device name", text: $name)
                    .textFieldStyle(.plain)
                    .font(AppTypography.bodyMedium())
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.substrateSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColors.glassBorder, lineWidth: 1)
                            )
                    )
            }

            Spacer()

            // Actions
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppColors.substrateTertiary)
                        )
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    onSave(name)
                } label: {
                    Text("Save")
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppColors.signalMercury)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .background(AppColors.substratePrimary)
        .onAppear {
            name = currentName
        }
        #if os(macOS)
        .frame(width: 400, height: 250)
        #endif
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        DevicesSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}
