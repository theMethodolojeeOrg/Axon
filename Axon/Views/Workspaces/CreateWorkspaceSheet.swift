//
//  CreateWorkspaceSheet.swift
//  Axon
//
//  Sheet for creating a new workspace with name, description, and tag selection.
//

import SwiftUI

struct CreateWorkspaceSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var viewModel: WorkspaceViewModel

    @State private var name = ""
    @State private var description = ""
    @State private var selectedTags: Set<String> = []
    @State private var newTagText = ""
    @State private var selectedIcon = "folder.fill"
    @State private var selectedColor = "#6B8E9F"

    var body: some View {
        #if os(macOS)
        // macOS: Direct content without NavigationView to avoid sidebar-like behavior
        sheetContent
            .frame(minWidth: 480, idealWidth: 560, minHeight: 500, idealHeight: 650)
        #else
        // iOS: Keep NavigationView for proper navigation
        NavigationView {
            sheetContent
                .navigationTitle("New Workspace")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
        }
        #endif
    }

    private var sheetContent: some View {
        ZStack {
            AppColors.substratePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    #if os(macOS)
                    // macOS header with title and cancel button
                    HStack {
                        Text("New Workspace")
                            .font(AppTypography.titleMedium())
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Button("Cancel") { dismiss() }
                            .foregroundColor(AppColors.textSecondary)
                    }
                    #endif

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
                        } else {
                            Text("No existing memory tags. Create new tags below.")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                                .padding(.vertical, 8)
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

                    // Create button
                    Button(action: createWorkspace) {
                        Text("Create Workspace")
                            .font(AppTypography.titleMedium())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canCreate ? AppColors.signalMercury : AppColors.substrateTertiary)
                            .foregroundColor(canCreate ? .white : AppColors.textTertiary)
                            .cornerRadius(12)
                    }
                    .disabled(!canCreate)
                    .padding(.top, 8)
                }
                .padding()
            }
        }
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addNewTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespaces).lowercased()
        if !tag.isEmpty {
            selectedTags.insert(tag)
            newTagText = ""
        }
    }

    private func createWorkspace() {
        viewModel.createWorkspace(
            name: name,
            description: description.isEmpty ? nil : description,
            tags: Array(selectedTags),
            iconName: selectedIcon,
            colorHex: selectedColor
        )
    }
}

// MARK: - Tag Picker Chip

struct TagPickerChip: View {
    let tag: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("#\(tag)")
                    .font(AppTypography.labelSmall())

                if count > 0 {
                    Text("(\(count))")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(isSelected ? .white.opacity(0.7) : AppColors.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? AppColors.signalMercury : AppColors.substrateSecondary)
            )
            .foregroundColor(isSelected ? .white : AppColors.textSecondary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    CreateWorkspaceSheet()
        .environmentObject(WorkspaceViewModel.shared)
}
