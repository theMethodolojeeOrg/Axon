//
//  IntentsSettingsView.swift
//  Axon
//
//  Settings view for configuring external app integrations (ports).
//  Allows enabling/disabling ports, importing shortcuts, and managing user ports.
//  Updated to use ToolCategoryAccordion-style pattern with 3-state toggles.
//

import SwiftUI

struct IntentsSettingsView: View {
    @StateObject private var portRegistry = PortRegistry.shared
    @State private var showingImportShortcut = false
    @State private var showingAddPort = false
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection

                // Search
                searchSection

                // Categories or filtered results
                if searchText.isEmpty {
                    categoriesSection
                } else {
                    searchResultsSection
                }

                // Import Shortcuts section
                importShortcutsSection

                // User-imported shortcuts
                if !portRegistry.importedShortcuts.isEmpty {
                    importedShortcutsSection
                }
            }
            .padding()
        }
        .background(AppColors.substratePrimary)
        .sheet(isPresented: $showingImportShortcut) {
            ImportShortcutSheet()
        }
        .sheet(isPresented: $showingAddPort) {
            AddCustomPortSheet()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App Integrations")
                .font(AppTypography.headlineLarge())
                .foregroundColor(AppColors.textPrimary)

            Text("Configure which external apps Axon can invoke through Siri, Shortcuts, and AI actions.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Search

    private var searchSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textTertiary)

            TextField("Search ports...", text: $searchText)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(10)
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(spacing: 12) {
            ForEach(PortCategory.allCases, id: \.self) { category in
                let categoryPorts = portRegistry.ports.filter { $0.category == category && $0.isBuiltIn }
                if !categoryPorts.isEmpty {
                    PortCategoryAccordion(
                        category: category,
                        ports: categoryPorts,
                        onCategoryToggle: { enabled in
                            // Toggle all ports in this category
                            for port in categoryPorts {
                                portRegistry.togglePort(id: port.id, enabled: enabled)
                            }
                        },
                        onPortToggle: { portId, enabled in
                            portRegistry.togglePort(id: portId, enabled: enabled)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsSection: some View {
        let filteredPorts = portRegistry.searchPorts(query: searchText)

        return VStack(alignment: .leading, spacing: 12) {
            Text("SEARCH RESULTS")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
                .padding(.horizontal, 4)

            if filteredPorts.isEmpty {
                Text("No ports found matching '\(searchText)'")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredPorts, id: \.id) { port in
                        PortToggleRow(
                            port: port,
                            isEnabled: port.isEnabled,
                            onToggle: { enabled in
                                portRegistry.togglePort(id: port.id, enabled: enabled)
                            }
                        )

                        if port.id != filteredPorts.last?.id {
                            Divider()
                                .background(AppColors.divider)
                                .padding(.leading, 60)
                        }
                    }
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Import Shortcuts

    private var importShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CUSTOM SHORTCUTS")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
                .padding(.horizontal, 4)

            Button(action: { showingImportShortcut = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.square.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.signalMercury)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import Shortcut by Name")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text("Add an Apple Shortcut to invoke via AI")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.signalMercury)
                }
                .padding()
            }
            .buttonStyle(.plain)
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
    }

    // MARK: - Imported Shortcuts List

    private var importedShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IMPORTED SHORTCUTS")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(portRegistry.importedShortcuts, id: \.id) { shortcut in
                    ImportedShortcutRow(shortcut: shortcut)

                    if shortcut.id != portRegistry.importedShortcuts.last?.id {
                        Divider()
                            .background(AppColors.divider)
                    }
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
    }
}

// MARK: - Port Category Toggle State

/// 3-state toggle state for port category headers
private enum PortCategoryToggleState {
    case allEnabled
    case partiallyEnabled
    case allDisabled
}

// MARK: - Port Category Accordion

/// Accordion component for organizing ports by category with 3-state toggle
private struct PortCategoryAccordion: View {
    let category: PortCategory
    let ports: [PortRegistryEntry]
    let onCategoryToggle: (Bool) -> Void
    let onPortToggle: (String, Bool) -> Void

    @State private var isExpanded = false

    private var categoryState: PortCategoryToggleState {
        let enabledCount = ports.filter { $0.isEnabled }.count
        if enabledCount == ports.count {
            return .allEnabled
        } else if enabledCount > 0 {
            return .partiallyEnabled
        } else {
            return .allDisabled
        }
    }

    private var enabledCount: Int {
        ports.filter { $0.isEnabled }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Accordion Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Category toggle (3-state)
                    PortCategoryToggleButton(
                        state: categoryState,
                        onToggle: {
                            let shouldEnable = categoryState != .allEnabled
                            onCategoryToggle(shouldEnable)
                        }
                    )

                    // Category icon
                    Image(systemName: category.icon)
                        .font(.system(size: 20))
                        .foregroundColor(categoryState != .allDisabled ? AppColors.signalMercury : AppColors.textTertiary)
                        .frame(width: 28)

                    // Category info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(category.displayName)
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            // Show enabled count
                            Text("\(enabledCount)/\(ports.count)")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }

                        Text(categoryDescription)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Expanded port list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(ports, id: \.id) { port in
                        PortToggleRow(
                            port: port,
                            isEnabled: port.isEnabled,
                            onToggle: { enabled in onPortToggle(port.id, enabled) }
                        )
                        .padding(.horizontal)

                        if port.id != ports.last?.id {
                            Divider()
                                .background(AppColors.divider)
                                .padding(.leading, 60)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(AppColors.substrateTertiary.opacity(0.5))
                .cornerRadius(8)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var categoryDescription: String {
        switch category {
        case .notes: return "Note-taking and writing apps"
        case .tasks: return "Task managers and reminders"
        case .calendar: return "Calendar and scheduling apps"
        case .automation: return "Shortcuts and automation tools"
        case .communication: return "Email, messaging, and calls"
        case .browser: return "Web browsers and reading"
        case .media: return "Music, podcasts, and video"
        case .developer: return "Development and coding tools"
        case .finance: return "Banking and finance apps"
        case .health: return "Health and fitness tracking"
        case .custom: return "User-defined integrations"
        }
    }
}

// MARK: - Port Category Toggle Button

/// 3-state toggle button for port category headers
private struct PortCategoryToggleButton: View {
    let state: PortCategoryToggleState
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
                    .frame(width: 24, height: 24)

                if state != .allDisabled {
                    Image(systemName: state == .allEnabled ? "checkmark" : "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch state {
        case .allEnabled:
            return AppColors.signalLichen
        case .partiallyEnabled:
            return AppColors.signalCopper
        case .allDisabled:
            return AppColors.textDisabled.opacity(0.3)
        }
    }
}

// MARK: - Port Toggle Row

private struct PortToggleRow: View {
    let port: PortRegistryEntry
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .tint(AppColors.signalMercury)
            .labelsHidden()

            Image(systemName: port.icon)
                .font(.system(size: 20))
                .foregroundColor(isEnabled ? AppColors.signalMercury : AppColors.textTertiary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(port.name)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(port.description)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Imported Shortcut Row

private struct ImportedShortcutRow: View {
    let shortcut: ImportedShortcut
    @StateObject private var portRegistry = PortRegistry.shared
    @State private var showingDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { shortcut.isEnabled },
                set: { newValue in
                    portRegistry.toggleShortcut(id: shortcut.id, enabled: newValue)
                }
            ))
            .toggleStyle(.switch)
            .tint(AppColors.signalMercury)
            .labelsHidden()

            Image(systemName: "bolt.square")
                .font(.system(size: 20))
                .foregroundColor(shortcut.isEnabled ? AppColors.signalMercury : AppColors.textTertiary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.name)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                if !shortcut.description.isEmpty {
                    Text(shortcut.description)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: { showingDeleteConfirm = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .alert("Delete Shortcut", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                portRegistry.removeShortcut(id: shortcut.id)
            }
        } message: {
            Text("Remove '\(shortcut.name)' from your imported shortcuts?")
        }
    }
}

// MARK: - Import Shortcut Sheet

private struct ImportShortcutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var portRegistry = PortRegistry.shared
    @State private var shortcutName = ""
    @State private var shortcutDescription = ""
    @State private var inputDescription = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Enter the exact name of an Apple Shortcut to make it available for AI invocation.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("SHORTCUT NAME")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    TextField("My Shortcut", text: $shortcutName)
                        .font(AppTypography.bodyMedium())
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("DESCRIPTION (OPTIONAL)")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    TextField("What does this shortcut do?", text: $shortcutDescription)
                        .font(AppTypography.bodyMedium())
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("INPUT DESCRIPTION (OPTIONAL)")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    TextField("What input does this shortcut expect?", text: $inputDescription)
                        .font(AppTypography.bodyMedium())
                        .textFieldStyle(.roundedBorder)
                }

                Spacer()

                Button(action: importShortcut) {
                    Text("Import Shortcut")
                        .font(AppTypography.bodyMedium(.medium))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(shortcutName.isEmpty ? AppColors.substrateSecondary : AppColors.signalMercury)
                        .foregroundColor(shortcutName.isEmpty ? AppColors.textTertiary : .white)
                        .cornerRadius(10)
                }
                .disabled(shortcutName.isEmpty)
            }
            .padding()
            .background(AppColors.substratePrimary)
            .navigationTitle("Import Shortcut")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func importShortcut() {
        portRegistry.importShortcut(
            name: shortcutName,
            description: shortcutDescription,
            inputDescription: inputDescription.isEmpty ? nil : inputDescription
        )
        dismiss()
    }
}

// MARK: - Add Custom Port Sheet (Placeholder)

private struct AddCustomPortSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                Text("Custom port creation coming soon...")
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.substratePrimary)
            .navigationTitle("Add Custom Port")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    IntentsSettingsView()
}

