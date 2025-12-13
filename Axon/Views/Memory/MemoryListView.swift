//
//  MemoryListView.swift
//  Axon
//
//  List of memories with filtering, multi-selection, and bulk actions
//

import SwiftUI

// MARK: - Sort Options

enum MemorySortOption: String, CaseIterable {
    case dateNewest = "Newest"
    case dateOldest = "Oldest"
    case confidenceHigh = "Confidence ↓"
    case confidenceLow = "Confidence ↑"
    case mostAccessed = "Most Accessed"

    var icon: String {
        switch self {
        case .dateNewest: return "arrow.down.circle"
        case .dateOldest: return "arrow.up.circle"
        case .confidenceHigh: return "chart.bar.fill"
        case .confidenceLow: return "chart.bar"
        case .mostAccessed: return "eye.fill"
        }
    }
}

// MARK: - Tag Info

struct TagInfo: Identifiable, Hashable {
    let tag: String
    let count: Int

    var id: String { tag }
}

// MARK: - Memory List View

struct MemoryListView: View {
    @StateObject private var memoryService = MemoryService.shared
    @State private var selectedType: MemoryType?
    @State private var searchText = ""
    @State private var showNewMemory = false
    @State private var selectedMemory: Memory?

    // Multi-selection
    @State private var isSelectionMode = false
    @State private var selectedIds: Set<String> = []

    // Sorting
    @State private var sortOption: MemorySortOption = .dateNewest

    // Archive filter
    @State private var showArchived = false

    // Tag filtering
    @State private var selectedTag: String?
    @State private var showAllTags = false

    // Confirmation dialogs
    @State private var showDeleteConfirmation = false
    @State private var showArchiveConfirmation = false

    // Computed: All unique tags with counts
    var tagInfos: [TagInfo] {
        var tagCounts: [String: Int] = [:]
        for memory in memoryService.memories {
            // Filter by archive status when counting
            if showArchived != memory.isArchived { continue }
            for tag in memory.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        return tagCounts.map { TagInfo(tag: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // Top tags for quick access (max 8)
    var topTags: [TagInfo] {
        Array(tagInfos.prefix(8))
    }

    var filteredMemories: [Memory] {
        var memories = memoryService.memories

        // Archive filter
        memories = memories.filter { $0.isArchived == showArchived }

        // Type filter
        if let type = selectedType {
            memories = memories.filter { $0.type == type }
        }

        // Tag filter
        if let tag = selectedTag {
            memories = memories.filter { $0.tags.contains(tag) }
        }

        // Search filter
        if !searchText.isEmpty {
            memories = memories.filter {
                $0.content.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }

        // Sorting
        switch sortOption {
        case .dateNewest:
            memories.sort { $0.createdAt > $1.createdAt }
        case .dateOldest:
            memories.sort { $0.createdAt < $1.createdAt }
        case .confidenceHigh:
            memories.sort { $0.confidence > $1.confidence }
        case .confidenceLow:
            memories.sort { $0.confidence < $1.confidence }
        case .mostAccessed:
            memories.sort { $0.accessCount > $1.accessCount }
        }

        return memories
    }

    var selectedCount: Int {
        selectedIds.count
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppColors.substratePrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar with sort button
                    HStack(spacing: 12) {
                        SearchBar(text: $searchText)

                        // Sort button
                        Menu {
                            ForEach(MemorySortOption.allCases, id: \.self) { option in
                                Button(action: { sortOption = option }) {
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
                            FilterChip(
                                title: showArchived ? "Archived" : "Active",
                                icon: showArchived ? "archivebox.fill" : "tray.full",
                                isSelected: true,
                                action: {
                                    withAnimation { showArchived.toggle() }
                                    selectedTag = nil // Reset tag filter when switching
                                }
                            )

                            Divider()
                                .frame(height: 24)

                            // Type filters
                            FilterChip(
                                title: "All",
                                isSelected: selectedType == nil,
                                action: { selectedType = nil }
                            )

                            ForEach(MemoryType.selectableCases, id: \.self) { type in
                                FilterChip(
                                    title: type.displayName,
                                    icon: type.icon,
                                    isSelected: selectedType == type,
                                    action: { selectedType = type }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)

                    // Tag filter section (if we have tags)
                    if !topTags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("TAGS")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)

                                Spacer()

                                if tagInfos.count > 8 {
                                    Button(action: { showAllTags = true }) {
                                        Text("See All (\(tagInfos.count))")
                                            .font(AppTypography.labelSmall())
                                            .foregroundColor(AppColors.signalMercury)
                                    }
                                }
                            }
                            .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    // Clear tag filter
                                    if selectedTag != nil {
                                        Button(action: { selectedTag = nil }) {
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

                                    ForEach(topTags) { tagInfo in
                                        TagChip(
                                            tagInfo: tagInfo,
                                            isSelected: selectedTag == tagInfo.tag,
                                            action: {
                                                if selectedTag == tagInfo.tag {
                                                    selectedTag = nil
                                                } else {
                                                    selectedTag = tagInfo.tag
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
                    if isSelectionMode {
                        SelectionBar(
                            selectedCount: selectedCount,
                            totalCount: filteredMemories.count,
                            showArchived: showArchived,
                            onSelectAll: { selectAll() },
                            onDeselectAll: { selectedIds.removeAll() },
                            onDelete: { showDeleteConfirmation = true },
                            onArchive: { showArchiveConfirmation = true },
                            onCancel: { exitSelectionMode() }
                        )
                    }

                    // Memories list
                    if filteredMemories.isEmpty && !memoryService.isLoading {
                        emptyStateView
                    } else {
                        List {
                            ForEach(filteredMemories) { memory in
                                MemoryRow(
                                    memory: memory,
                                    isSelectionMode: isSelectionMode,
                                    isSelected: selectedIds.contains(memory.id),
                                    onTap: {
                                        if isSelectionMode {
                                            toggleSelection(memory.id)
                                        } else {
                                            selectedMemory = memory
                                        }
                                    },
                                    onLongPress: {
                                        if !isSelectionMode {
                                            enterSelectionMode(with: memory.id)
                                        }
                                    },
                                    onDelete: { deleteMemory(memory) },
                                    onArchive: { toggleArchive(memory) },
                                    onPin: { togglePin(memory) }
                                )
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                        }
                        .listStyle(.plain)
                    }

                    if memoryService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppColors.signalMercury))
                    }
                }
            }
            .navigationTitle("Memory")
            .toolbar {
                ToolbarItem {
                    if !isSelectionMode {
                        Button(action: { enterSelectionMode() }) {
                            Text("Select")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.signalMercury)
                        }
                    }
                }

                ToolbarItem {
                    if !isSelectionMode {
                        Button(action: { showNewMemory = true }) {
                            Image(systemName: "plus")
                                .foregroundColor(AppColors.signalMercury)
                        }
                    }
                }
            }
            .sheet(isPresented: $showNewMemory) {
                NewMemorySheet()
            }
            .sheet(item: $selectedMemory) { memory in
                MemoryDetailView(memory: memory)
            }
            .sheet(isPresented: $showAllTags) {
                AllTagsSheet(
                    tagInfos: tagInfos,
                    selectedTag: $selectedTag,
                    onDismiss: { showAllTags = false }
                )
            }
            .alert("Delete \(selectedCount) Memories?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { deleteSelected() }
            } message: {
                Text("This action cannot be undone.")
            }
            .alert(showArchived ? "Restore \(selectedCount) Memories?" : "Archive \(selectedCount) Memories?", isPresented: $showArchiveConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button(showArchived ? "Restore" : "Archive") { archiveSelected() }
            } message: {
                Text(showArchived ? "These memories will be moved back to active." : "Archived memories can be restored later.")
            }
            .task {
                await loadMemories()
            }
            .refreshable {
                await loadMemories()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image("AxonLogoTemplate")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(AppColors.signalMercury.opacity(0.5))

            Text(emptyStateTitle)
                .font(AppTypography.headlineSmall())
                .foregroundColor(AppColors.textPrimary)

            Text(emptyStateMessage)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var emptyStateTitle: String {
        if showArchived {
            return "No Archived Memories"
        } else if selectedTag != nil {
            return "No Memories with Tag"
        } else if selectedType != nil {
            return "No \(selectedType!.displayName) Memories"
        } else if !searchText.isEmpty {
            return "No Matches Found"
        } else {
            return "No Memories Yet"
        }
    }

    private var emptyStateMessage: String {
        if showArchived {
            return "Archived memories will appear here"
        } else if selectedTag != nil {
            return "No memories tagged with #\(selectedTag!)"
        } else if selectedType != nil || !searchText.isEmpty {
            return "Try adjusting your filters"
        } else {
            return "Memories will be created automatically as you chat"
        }
    }

    // MARK: - Selection Mode

    private func enterSelectionMode(with id: String? = nil) {
        isSelectionMode = true
        selectedIds.removeAll()
        if let id = id {
            selectedIds.insert(id)
        }
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedIds.removeAll()
    }

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func selectAll() {
        selectedIds = Set(filteredMemories.map { $0.id })
    }

    // MARK: - Actions

    private func loadMemories() async {
        do {
            try await memoryService.getMemories(limit: 100, type: selectedType)
        } catch {
            print("Error loading memories: \(error.localizedDescription)")
        }
    }

    private func deleteMemory(_ memory: Memory) {
        Task {
            do {
                try await memoryService.deleteMemory(id: memory.id)
            } catch {
                print("Error deleting memory: \(error.localizedDescription)")
            }
        }
    }

    private func deleteSelected() {
        Task {
            for id in selectedIds {
                do {
                    try await memoryService.deleteMemory(id: id)
                } catch {
                    print("Error deleting memory \(id): \(error.localizedDescription)")
                }
            }
            exitSelectionMode()
        }
    }

    private func toggleArchive(_ memory: Memory) {
        Task {
            do {
                var newMetadata = memory.metadata
                newMetadata["isArchived"] = .bool(!memory.isArchived)

                _ = try await memoryService.updateMemory(
                    id: memory.id,
                    metadata: newMetadata
                )
            } catch {
                print("Error toggling archive: \(error.localizedDescription)")
            }
        }
    }

    private func archiveSelected() {
        let newArchiveState = !showArchived // If viewing archived, we're restoring
        Task {
            for id in selectedIds {
                if let memory = memoryService.memories.first(where: { $0.id == id }) {
                    do {
                        var newMetadata = memory.metadata
                        newMetadata["isArchived"] = .bool(newArchiveState)

                        _ = try await memoryService.updateMemory(
                            id: id,
                            metadata: newMetadata
                        )
                    } catch {
                        print("Error archiving memory \(id): \(error.localizedDescription)")
                    }
                }
            }
            exitSelectionMode()
        }
    }

    private func togglePin(_ memory: Memory) {
        Task {
            do {
                var newMetadata = memory.metadata
                newMetadata["isPinned"] = .bool(!memory.isPinned)

                _ = try await memoryService.updateMemory(
                    id: memory.id,
                    metadata: newMetadata
                )
            } catch {
                print("Error toggling pin: \(error.localizedDescription)")
            }
        }
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

private struct SelectionBar: View {
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

private struct TagChip: View {
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
                    SearchBar(text: $searchText)
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
    }
}

// MARK: - Memory Card

struct MemoryCard: View {
    let memory: Memory
    @StateObject private var learningService = LearningLoopService.shared

    /// Get learning data for this memory (if tracked)
    private var learningData: MemoryLearningData? {
        learningService.learningData[memory.id]
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

struct SearchBar: View {
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

struct FilterChip: View {
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

// MARK: - Preview

#Preview {
    MemoryListView()
}
