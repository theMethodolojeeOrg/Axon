//
//  MemoryListView.swift
//  Axon
//
//  Memory content view with filtering, multi-selection, and bulk actions
//  Note: MemorySortOption and TagInfo are defined in MemoryViewModel.swift
//

import SwiftUI

// MARK: - Memory Content View

struct MemoryContentView: View {
    @EnvironmentObject var viewModel: MemoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Search bar with sort button
            HStack(spacing: 12) {
                MemorySearchBar(text: $viewModel.searchText)

                // Sort button
                Menu {
                    ForEach(MemorySortOption.allCases, id: \.self) { option in
                        Button(action: { viewModel.sortOption = option }) {
                            Label(option.rawValue, systemImage: option.icon)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.signalMercury)
                        .frame(width: 44, height: 44)
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            .padding(.top)

            // Archive toggle + Type filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Archive toggle
                    MemoryFilterChip(
                        title: viewModel.showArchived ? "Archived" : "Active",
                        icon: viewModel.showArchived ? "archivebox.fill" : "tray.full",
                        isSelected: true,
                        action: {
                            withAnimation { viewModel.showArchived.toggle() }
                            viewModel.selectedTag = nil // Reset tag filter when switching
                        }
                    )

                    Divider()
                        .frame(height: 24)

                    // Type filters
                    MemoryFilterChip(
                        title: "All",
                        isSelected: viewModel.selectedType == nil,
                        action: { viewModel.selectedType = nil }
                    )

                    ForEach(MemoryType.selectableCases, id: \.self) { type in
                        MemoryFilterChip(
                            title: type.displayName,
                            icon: type.icon,
                            isSelected: viewModel.selectedType == type,
                            action: { viewModel.selectedType = type }
                        )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            // Tag filter section (if we have tags)
            if !viewModel.topTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("TAGS")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)

                        Spacer()

                        if viewModel.tagInfos.count > 8 {
                            Button(action: { viewModel.showAllTags = true }) {
                                Text("See All (\(viewModel.tagInfos.count))")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.signalMercury)
                            }
                        }
                    }
                    .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // Clear tag filter
                            if viewModel.selectedTag != nil {
                                Button(action: { viewModel.selectedTag = nil }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                        Text("Clear")
                                            .font(AppTypography.labelSmall())
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(AppColors.signalHematite.opacity(0.2))
                                    .foregroundColor(AppColors.signalHematite)
                                    .cornerRadius(14)
                                }
                            }

                            ForEach(viewModel.topTags) { tagInfo in
                                MemoryTagChip(
                                    tagInfo: tagInfo,
                                    isSelected: viewModel.selectedTag == tagInfo.tag,
                                    action: {
                                        if viewModel.selectedTag == tagInfo.tag {
                                            viewModel.selectedTag = nil
                                        } else {
                                            viewModel.selectedTag = tagInfo.tag
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 8)
            }

            // Selection mode bar
            if viewModel.isSelectionMode {
                MemorySelectionBar(
                    selectedCount: viewModel.selectedCount,
                    totalCount: viewModel.filteredMemories.count,
                    showArchived: viewModel.showArchived,
                    onSelectAll: { viewModel.selectAll() },
                    onDeselectAll: { viewModel.deselectAll() },
                    onDelete: { viewModel.showDeleteConfirmation = true },
                    onArchive: { viewModel.showArchiveConfirmation = true },
                    onCancel: { viewModel.exitSelectionMode() }
                )
            }

            // Toolbar area for Select/Add buttons
            if !viewModel.isSelectionMode {
                HStack {
                    Spacer()
                    
                    Button(action: { viewModel.enterSelectionMode() }) {
                        Text("Select")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.signalMercury)
                    }
                    .padding(.trailing, 8)
                    
                    Button(action: { viewModel.showNewMemory = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(AppColors.signalMercury)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Memories list
            if viewModel.filteredMemories.isEmpty && !viewModel.isLoading {
                emptyStateView
            } else {
                List {
                    ForEach(viewModel.filteredMemories) { memory in
                        MemoryRow(
                            memory: memory,
                            isSelectionMode: viewModel.isSelectionMode,
                            isSelected: viewModel.selectedIds.contains(memory.id),
                            onTap: {
                                if viewModel.isSelectionMode {
                                    viewModel.toggleSelection(memory.id)
                                } else {
                                    viewModel.selectedMemory = memory
                                }
                            },
                            onLongPress: {
                                if !viewModel.isSelectionMode {
                                    viewModel.enterSelectionMode(with: memory.id)
                                }
                            },
                            onDelete: { viewModel.deleteMemory(memory) },
                            onArchive: { viewModel.toggleArchive(memory) },
                            onPin: { viewModel.togglePin(memory) }
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }

            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.signalMercury))
            }
        }
        .sheet(isPresented: $viewModel.showNewMemory) {
            NewMemorySheet()
        }
        .sheet(item: $viewModel.selectedMemory) { memory in
            MemoryDetailView(memory: memory)
        }
        .sheet(isPresented: $viewModel.showAllTags) {
            AllTagsSheet(
                tagInfos: viewModel.tagInfos,
                selectedTag: $viewModel.selectedTag,
                onDismiss: { viewModel.showAllTags = false }
            )
        }
        .alert("Delete \(viewModel.selectedCount) Memories?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { viewModel.deleteSelected() }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert(viewModel.showArchived ? "Restore \(viewModel.selectedCount) Memories?" : "Archive \(viewModel.selectedCount) Memories?", isPresented: $viewModel.showArchiveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(viewModel.showArchived ? "Restore" : "Archive") { viewModel.archiveSelected() }
        } message: {
            Text(viewModel.showArchived ? "These memories will be moved back to active." : "Archived memories can be restored later.")
        }
        .task {
            await viewModel.loadMemories()
        }
        .refreshable {
            await viewModel.loadMemories()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image("AxonLogoTemplate")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(AppColors.signalMercury.opacity(0.5))

            Text(viewModel.emptyStateTitle)
                .font(AppTypography.headlineSmall())
                .foregroundColor(AppColors.textPrimary)

            Text(viewModel.emptyStateMessage)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Memory Row

private struct MemoryRow: View {
    let memory: Memory
    let isSelectionMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onDelete: () -> Void
    let onArchive: () -> Void
    let onPin: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textTertiary)
            }

            // Memory card
            MemoryCard(memory: memory)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture { onLongPress() }
        .swipeActions(edge: .trailing, allowsFullSwipe: !isSelectionMode) {
            if !isSelectionMode {
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button { onArchive() } label: {
                    Label(memory.isArchived ? "Restore" : "Archive", systemImage: "archivebox")
                }
                .tint(AppColors.signalHematite)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: !isSelectionMode) {
            if !isSelectionMode {
                Button { onPin() } label: {
                    Label(memory.isPinned ? "Unpin" : "Pin", systemImage: "pin")
                }
                .tint(AppColors.signalMercury)
            }
        }
    }
}

// MARK: - Selection Bar

private struct MemorySelectionBar: View {
    let selectedCount: Int
    let totalCount: Int
    let showArchived: Bool
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let onDelete: () -> Void
    let onArchive: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Cancel button
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                // Selection count
                Text("\(selectedCount) selected")
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                // Select all / Deselect all
                Button(action: selectedCount == totalCount ? onDeselectAll : onSelectAll) {
                    Text(selectedCount == totalCount ? "Deselect" : "Select All")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.signalMercury)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(AppColors.substrateSecondary)

            // Action buttons
            if selectedCount > 0 {
                HStack(spacing: 24) {
                    Button(action: onArchive) {
                        VStack(spacing: 4) {
                            Image(systemName: showArchived ? "tray.and.arrow.up" : "archivebox")
                                .font(.system(size: 20))
                            Text(showArchived ? "Restore" : "Archive")
                                .font(AppTypography.labelSmall())
                        }
                        .foregroundColor(AppColors.signalMercury)
                    }

                    Button(action: onDelete) {
                        VStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 20))
                            Text("Delete")
                                .font(AppTypography.labelSmall())
                        }
                        .foregroundColor(AppColors.signalHematite)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(AppColors.substrateSecondary)
            }
        }
    }
}

// MARK: - Tag Chip

private struct MemoryTagChip: View {
    let tagInfo: TagInfo
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("#\(tagInfo.tag)")
                    .font(AppTypography.labelSmall())

                Text("\(tagInfo.count)")
                    .font(AppTypography.labelSmall())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isSelected ? .white.opacity(0.3) : AppColors.substrateTertiary)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? AppColors.signalMercury : AppColors.substrateSecondary)
            .foregroundColor(isSelected ? .white : AppColors.textSecondary)
            .cornerRadius(14)
        }
    }
}

// MARK: - All Tags Sheet

private struct AllTagsSheet: View {
    let tagInfos: [TagInfo]
    @Binding var selectedTag: String?
    let onDismiss: () -> Void

    @State private var searchText = ""

    var filteredTags: [TagInfo] {
        if searchText.isEmpty {
            return tagInfos
        }
        return tagInfos.filter { $0.tag.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppColors.substratePrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    MemorySearchBar(text: $searchText)
                        .padding()

                    List {
                        ForEach(filteredTags) { tagInfo in
                            Button(action: {
                                selectedTag = tagInfo.tag
                                onDismiss()
                            }) {
                                HStack {
                                    Text("#\(tagInfo.tag)")
                                        .font(AppTypography.bodyMedium())
                                        .foregroundColor(AppColors.textPrimary)

                                    Spacer()

                                    Text("\(tagInfo.count) memories")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.textTertiary)

                                    if selectedTag == tagInfo.tag {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(AppColors.signalMercury)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(AppColors.substrateSecondary)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("All Tags")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem {
                    Button("Done") { onDismiss() }
                        .foregroundColor(AppColors.signalMercury)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 450, minHeight: 400, idealHeight: 500)
        #endif
    }
}

// MARK: - Memory Card

struct MemoryCard: View {
    let memory: Memory
    @StateObject private var learningService = LearningLoopService.shared
    @State private var showResetConfirmation = false

    /// Get learning data for this memory (if tracked)
    private var learningData: MemoryLearningData? {
        learningService.learningData[memory.id]
    }

    /// Check if memory is suspicious (low reliability after multiple uses)
    private var isSuspicious: Bool {
        guard let learning = learningData else { return false }
        return learning.reliability < 0.5 && (learning.successCount + learning.failureCount) >= 3
    }

    /// Confidence color based on value
    private var confidenceColor: Color {
        if memory.confidence >= 0.8 {
            return AppColors.accentSuccess
        } else if memory.confidence >= 0.5 {
            return AppColors.signalMercury
        } else {
            return AppColors.signalHematite
        }
    }

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                // Suspicious memory banner
                if isSuspicious {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.signalCopper)

                        Text("Suspicious - frequently contradicted")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.signalCopper)

                        Spacer()

                        Button(action: { showResetConfirmation = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12))
                                Text("Reset")
                                    .font(AppTypography.labelSmall())
                            }
                            .foregroundColor(AppColors.signalMercury)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.signalMercury.opacity(0.2))
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(10)
                    .background(AppColors.signalCopper.opacity(0.15))
                    .cornerRadius(8)
                }

                // Header
                HStack {
                    // Pin indicator
                    if memory.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.signalMercury)
                    }

                    Label(memory.type.displayName, systemImage: memory.type.icon)
                        .font(AppTypography.labelMedium())
                        .foregroundColor(colorForType(memory.type))

                    Spacer()

                    // Confidence badge with color coding
                    HStack(spacing: 4) {
                        if let learning = learningData, learning.successCount + learning.failureCount > 0 {
                            // Show learning indicator
                            Image(systemName: learning.reliability >= 0.7 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(learning.reliability >= 0.7 ? AppColors.accentSuccess : AppColors.signalHematite)
                        }
                        Text("\(Int(memory.confidence * 100))%")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(confidenceColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.substrateTertiary)
                    .cornerRadius(8)
                }

                // Content
                Text(memory.content)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(3)

                // Tags
                if !memory.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(memory.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.signalMercury)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppColors.signalMercury.opacity(0.2))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }

                // Footer
                HStack {
                    Text(memory.createdAt, style: .relative)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    Spacer()

                    if memory.accessCount > 0 {
                        Label("\(memory.accessCount)", systemImage: "eye")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
        }
        .alert("Reset Learning Data?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                learningService.resetLearningData(for: memory.id)
            }
        } message: {
            Text("This will clear all learning history for this memory, giving it a fresh start. The memory content will not be changed.")
        }
    }

    private func colorForType(_ type: MemoryType) -> Color {
        switch type {
        case .allocentric: return AppColors.signalMercury
        case .egoic: return AppColors.signalLichen
        case .fact: return AppColors.signalMercury
        case .procedure: return AppColors.signalLichen
        case .context: return AppColors.signalCopper
        case .relationship: return AppColors.signalHematite
        case .question: return AppColors.signalCopper
        case .insight: return AppColors.signalLichen
        case .learning: return AppColors.signalLichen
        case .preference: return AppColors.signalMercury
        }
    }
}

// MARK: - Search Bar

struct MemorySearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textSecondary)

            TextField("Search memories...", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .padding(12)
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
    }
}

// MARK: - Filter Chip

struct MemoryFilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(AppTypography.labelSmall())
                }
                Text(title)
                    .font(AppTypography.labelMedium())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? AppColors.signalMercury : AppColors.substrateSecondary)
            .foregroundColor(isSelected ? .white : AppColors.textSecondary)
            .cornerRadius(20)
        }
    }
}

// MARK: - New Memory Sheet

struct NewMemorySheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var memoryService = MemoryService.shared
    @State private var content = ""
    @State private var selectedType = MemoryType.allocentric
    @State private var confidence: Double = 0.8
    @State private var tagsText = ""

    var body: some View {
        NavigationView {
            ZStack {
                AppColors.substratePrimary
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Content
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Content")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        TextEditor(text: $content)
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)
                            .frame(height: 120)
                            .padding(8)
                            .background(AppColors.substrateTertiary)
                            .cornerRadius(8)
                    }

                    // Type
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        Picker("Type", selection: $selectedType) {
                            ForEach(MemoryType.selectableCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }

                    // Tags
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags (comma separated)")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        TextField("work, project, idea", text: $tagsText)
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)
                            .padding(12)
                            .background(AppColors.substrateTertiary)
                            .cornerRadius(8)
                    }

                    // Confidence
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Confidence")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textSecondary)

                            Spacer()

                            Text("\(Int(confidence * 100))%")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textPrimary)
                        }

                        Slider(value: $confidence, in: 0...1)
                            .accentColor(AppColors.signalMercury)
                    }

                    Button(action: createMemory) {
                        Text("Create Memory")
                            .font(AppTypography.titleMedium())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppColors.signalMercury)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(content.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("New Memory")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 450, minHeight: 450, idealHeight: 550)
        #endif
    }

    private func createMemory() {
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        Task {
            do {
                _ = try await memoryService.createMemory(
                    content: content,
                    type: selectedType,
                    confidence: confidence,
                    tags: tags
                )
                dismiss()
            } catch {
                print("Error creating memory: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Legacy MemoryListView (for backwards compatibility)
// This maintains the old API for any code still referencing MemoryListView directly

struct MemoryListView: View {
    var body: some View {
        MemoryView()
    }
}

// MARK: - Preview

#Preview {
    MemoryContentView()
        .environmentObject(MemoryViewModel.shared)
}
