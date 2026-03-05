//
//  EditWorkspaceSheet.swift
//  Axon
//
//  Sheet for editing an existing workspace.
//

import SwiftUI

struct EditWorkspaceSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var viewModel: WorkspaceViewModel

    let workspace: Workspace

    @State private var name: String
    @State private var description: String
    @State private var selectedTags: Set<String>
    @State private var newTagText = ""
    @State private var selectedIcon: String
    @State private var selectedColor: String

    init(workspace: Workspace) {
        self.workspace = workspace
        _name = State(initialValue: workspace.name)
        _description = State(initialValue: workspace.description ?? "")
        _selectedTags = State(initialValue: Set(workspace.associatedTags))
        _selectedIcon = State(initialValue: workspace.iconName ?? "folder.fill")
        _selectedColor = State(initialValue: workspace.colorHex ?? "#6B8E9F")
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppColors.substratePrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Icon and Color selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("APPEARANCE")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)

                            HStack(spacing: 16) {
                                // Selected icon preview
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: selectedColor).opacity(0.2))
                                        .frame(width: 64, height: 64)

                                    Image(systemName: selectedIcon)
                                        .font(.system(size: 28))
                                        .foregroundColor(Color(hex: selectedColor))
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    // Icon picker
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(Workspace.availableIcons, id: \.self) { icon in
                                                Button(action: { selectedIcon = icon }) {
                                                    Image(systemName: icon)
                                                        .font(.system(size: 16))
                                                        .frame(width: 32, height: 32)
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 6)
                                                                .fill(selectedIcon == icon
                                                                      ? AppColors.signalMercury.opacity(0.2)
                                                                      : AppColors.substrateSecondary)
                                                        )
                                                        .foregroundColor(selectedIcon == icon
                                                                        ? AppColors.signalMercury
                                                                        : AppColors.textSecondary)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                        }
                                    }

                                    // Color picker
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(Workspace.availableColors, id: \.self) { hex in
                                                Button(action: { selectedColor = hex }) {
                                                    Circle()
                                                        .fill(Color(hex: hex))
                                                        .frame(width: 24, height: 24)
                                                        .overlay(
                                                            Circle()
                                                                .stroke(selectedColor == hex
                                                                       ? AppColors.textPrimary
                                                                       : Color.clear, lineWidth: 2)
                                                        )
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Name field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NAME")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)

                            TextField("Workspace name", text: $name)
                                .textFieldStyle(AppTextFieldStyle())
                        }

                        // Description field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DESCRIPTION")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)

                            TextField("Optional description", text: $description)
                                .textFieldStyle(AppTextFieldStyle())
                        }

                        // Tag picker section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("MEMORY TAGS")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)

                            Text("Select existing tags or create new ones to scope shared knowledge")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)

                            // Existing tags
                            if !viewModel.availableTags.isEmpty {
                                FlowLayout(spacing: 8) {
                                    ForEach(viewModel.availableTags) { tagInfo in
                                        TagPickerChip(
                                            tag: tagInfo.tag,
                                            count: tagInfo.count,
                                            isSelected: selectedTags.contains(tagInfo.tag)
                                        ) {
                                            if selectedTags.contains(tagInfo.tag) {
                                                selectedTags.remove(tagInfo.tag)
                                            } else {
                                                selectedTags.insert(tagInfo.tag)
                                            }
                                        }
                                    }
                                }
                            }

                            // Create new tag
                            HStack {
                                TextField("Add new tag", text: $newTagText)
                                    .textFieldStyle(AppTextFieldStyle())
                                    .onSubmit {
                                        addNewTag()
                                    }

                                Button(action: addNewTag) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(newTagText.trimmingCharacters(in: .whitespaces).isEmpty
                                                        ? AppColors.textTertiary
                                                        : AppColors.signalMercury)
                                }
                                .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                            }

                            // Selected tags preview
                            if !selectedTags.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Selected Tags (\(selectedTags.count))")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.textSecondary)

                                    FlowLayout(spacing: 6) {
                                        ForEach(Array(selectedTags).sorted(), id: \.self) { tag in
                                            HStack(spacing: 4) {
                                                Text("#\(tag)")
                                                    .font(AppTypography.labelSmall())

                                                Button(action: { selectedTags.remove(tag) }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.system(size: 12))
                                                }
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(AppColors.signalMercury)
                                            .cornerRadius(12)
                                        }
                                    }
                                }
                            }
                        }

                        // Save button
                        Button(action: saveWorkspace) {
                            Text("Save Changes")
                                .font(AppTypography.titleMedium())
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(canSave ? AppColors.signalMercury : AppColors.substrateTertiary)
                                .foregroundColor(canSave ? .white : AppColors.textTertiary)
                                .cornerRadius(12)
                        }
                        .disabled(!canSave)
                        .padding(.top, 8)
                    }
                    .padding()
                }
            }
            .navigationTitle("Edit Workspace")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addNewTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespaces).lowercased()
        if !tag.isEmpty {
            selectedTags.insert(tag)
            newTagText = ""
        }
    }

    private func saveWorkspace() {
        viewModel.updateWorkspace(
            workspace,
            name: name,
            description: description.isEmpty ? nil : description,
            tags: Array(selectedTags),
            iconName: selectedIcon,
            colorHex: selectedColor
        )
    }
}

// MARK: - Preview

#Preview {
    EditWorkspaceSheet(workspace: Workspace(
        name: "Test Workspace",
        description: "A test workspace",
        associatedTags: ["test", "demo"],
        iconName: "folder.fill",
        colorHex: "#6B8E9F"
    ))
    .environmentObject(WorkspaceViewModel.shared)
}
