//
//  MemoryListView.swift
//  Axon
//
//  List of memories with filtering
//

import SwiftUI

struct MemoryListView: View {
    @StateObject private var memoryService = MemoryService.shared
    @State private var selectedType: MemoryType?
    @State private var searchText = ""
    @State private var showNewMemory = false
    @State private var selectedMemory: Memory?

    var filteredMemories: [Memory] {
        var memories = memoryService.memories

        if let type = selectedType {
            memories = memories.filter { $0.type == type }
        }

        if !searchText.isEmpty {
            memories = memories.filter {
                $0.content.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }

        return memories
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppColors.substratePrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    SearchBar(text: $searchText)
                        .padding()

                    // Type filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
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
                    .padding(.bottom)

                    // Memories list
                    if filteredMemories.isEmpty && !memoryService.isLoading {
                        VStack(spacing: 20) {
                            Image("AxonLogoTemplate")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .foregroundColor(AppColors.signalMercury.opacity(0.5))

                            Text("No Memories Found")
                                .font(AppTypography.headlineSmall())
                                .foregroundColor(AppColors.textPrimary)

                            Text("Memories will be created automatically as you chat")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else {
                        List {
                            ForEach(filteredMemories) { memory in
                                MemoryCard(memory: memory)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedMemory = memory
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteMemory(memory)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        
                                        Button {
                                            toggleArchive(memory)
                                        } label: {
                                            Label(memory.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                                        }
                                        .tint(AppColors.signalHematite)
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            togglePin(memory)
                                        } label: {
                                            Label(memory.isPinned ? "Unpin" : "Pin", systemImage: "pin")
                                        }
                                        .tint(AppColors.signalMercury)
                                    }
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showNewMemory = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(AppColors.signalMercury)
                    }
                }
            }
            .sheet(isPresented: $showNewMemory) {
                NewMemorySheet()
            }
            .sheet(item: $selectedMemory) { memory in
                MemoryDetailView(memory: memory)
            }
            .task {
                await loadMemories()
            }
            .refreshable {
                await loadMemories()
            }
        }
    }

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

// MARK: - Memory Card

struct MemoryCard: View {
    let memory: Memory

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Label(memory.type.displayName, systemImage: memory.type.icon)
                        .font(AppTypography.labelMedium())
                        .foregroundColor(colorForType(memory.type))

                    Spacer()

                    // Confidence badge
                    Text("\(Int(memory.confidence * 100))%")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
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
        case .fact: return AppColors.signalMercury
        case .procedure: return AppColors.signalLichen
        case .context: return AppColors.signalCopper
        case .relationship: return AppColors.signalHematite
        @unknown default:
            return AppColors.signalMercury
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    private func createMemory() {
        Task {
            do {
                _ = try await memoryService.createMemory(
                    content: content,
                    type: selectedType,
                    confidence: confidence
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

