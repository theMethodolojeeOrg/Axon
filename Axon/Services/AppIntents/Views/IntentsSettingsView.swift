//
//  IntentsSettingsView.swift
//  Axon
//
//  Settings view for configuring external app integrations (ports).
//  Allows enabling/disabling ports, importing shortcuts, and managing user ports.
//

import SwiftUI

struct IntentsSettingsView: View {
    @StateObject private var portRegistry = PortRegistry.shared
    @State private var selectedCategory: PortCategory? = nil
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
        VStack(spacing: 16) {
            ForEach(PortCategory.allCases, id: \.self) { category in
                let categoryPorts = portRegistry.ports.filter { $0.category == category && $0.isBuiltIn }
                if !categoryPorts.isEmpty {
                    CategoryAccordion(
                        category: category,
                        ports: categoryPorts
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
                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(filteredPorts, id: \.id) { port in
                            PortToggleRow(port: port)

                            if port.id != filteredPorts.last?.id {
                                Divider()
                                    .background(AppColors.divider)
                            }
                        }
                    }
                }
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

            GlassCard(padding: 0) {
                Button(action: { showingImportShortcut = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.square.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.signalMercury)

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
            }
        }
    }

    // MARK: - Imported Shortcuts List

    private var importedShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IMPORTED SHORTCUTS")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
                .padding(.horizontal, 4)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(portRegistry.importedShortcuts, id: \.id) { shortcut in
                        ImportedShortcutRow(shortcut: shortcut)

                        if shortcut.id != portRegistry.importedShortcuts.last?.id {
                            Divider()
                                .background(AppColors.divider)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Category Accordion

private struct CategoryAccordion: View {
    let category: PortCategory
    let ports: [PortRegistryEntry]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    Image(systemName: category.icon)
                        .font(.system(size: 18))
                        .foregroundColor(AppColors.signalMercury)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.displayName)
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text("\(ports.filter { $0.isEnabled }.count)/\(ports.count) enabled")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(isExpanded ? 10 : 10)
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(ports, id: \.id) { port in
                        Divider()
                            .background(AppColors.divider)

                        PortToggleRow(port: port)
                    }
                }
                .background(AppColors.substrateSecondary.opacity(0.7))
                .cornerRadius(10)
                .padding(.top, -8)
            }
        }
    }
}

// MARK: - Port Toggle Row

private struct PortToggleRow: View {
    let port: PortRegistryEntry
    @StateObject private var portRegistry = PortRegistry.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: port.icon)
                .font(.system(size: 16))
                .foregroundColor(port.isEnabled ? AppColors.signalMercury : AppColors.textTertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(port.name)
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(port.isEnabled ? AppColors.textPrimary : AppColors.textSecondary)

                Text(port.appName)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { port.isEnabled },
                set: { newValue in
                    portRegistry.togglePort(id: port.id, enabled: newValue)
                }
            ))
            .toggleStyle(.switch)
            .tint(AppColors.signalMercury)
            .labelsHidden()
        }
        .padding()
    }
}

// MARK: - Imported Shortcut Row

private struct ImportedShortcutRow: View {
    let shortcut: ImportedShortcut
    @StateObject private var portRegistry = PortRegistry.shared
    @State private var showingDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.square")
                .font(.system(size: 16))
                .foregroundColor(shortcut.isEnabled ? AppColors.signalMercury : AppColors.textTertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.name)
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(shortcut.isEnabled ? AppColors.textPrimary : AppColors.textSecondary)

                if !shortcut.description.isEmpty {
                    Text(shortcut.description)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
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

            Toggle("", isOn: Binding(
                get: { shortcut.isEnabled },
                set: { newValue in
                    portRegistry.toggleShortcut(id: shortcut.id, enabled: newValue)
                }
            ))
            .toggleStyle(.switch)
            .tint(AppColors.signalMercury)
            .labelsHidden()
        }
        .padding()
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
            .navigationBarTitleDisplayMode(.inline)
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
            .navigationBarTitleDisplayMode(.inline)
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
