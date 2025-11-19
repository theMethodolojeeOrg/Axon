//
//  MemoryDetailView.swift
//  Axon
//
//  Detail view for viewing and editing a memory
//

import SwiftUI

struct MemoryDetailView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var memoryService = MemoryService.shared
    
    let memory: Memory
    
    @State private var content: String
    @State private var selectedType: MemoryType
    @State private var confidence: Double
    @State private var tags: String
    @State private var context: String
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    
    init(memory: Memory) {
        self.memory = memory
        _content = State(initialValue: memory.content)
        _selectedType = State(initialValue: memory.type)
        _confidence = State(initialValue: memory.confidence)
        _tags = State(initialValue: memory.tags.joined(separator: ", "))
        _context = State(initialValue: memory.context ?? "")
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppColors.substratePrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header Info
                        HStack {
                            Label(memory.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                            
                            Spacer()
                            
                            if memory.isPinned {
                                Image(systemName: "pin.fill")
                                    .foregroundColor(AppColors.signalMercury)
                            }
                            
                            if memory.isArchived {
                                Text("ARCHIVED")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.signalHematite)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppColors.signalHematite.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Content
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Content")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textSecondary)
                            
                            if isEditing {
                                TextEditor(text: $content)
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                                    .frame(minHeight: 120)
                                    .padding(8)
                                    .background(AppColors.substrateTertiary)
                                    .cornerRadius(8)
                            } else {
                                Text(memory.content)
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .background(AppColors.substrateSecondary)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Context (New Field)
                        if isEditing || !context.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Context")
                                    .font(AppTypography.labelMedium())
                                    .foregroundColor(AppColors.textSecondary)
                                
                                if isEditing {
                                    TextEditor(text: $context)
                                        .font(AppTypography.bodyMedium())
                                        .foregroundColor(AppColors.textPrimary)
                                        .frame(minHeight: 80)
                                        .padding(8)
                                        .background(AppColors.substrateTertiary)
                                        .cornerRadius(8)
                                } else {
                                    Text(context)
                                        .font(AppTypography.bodyMedium())
                                        .foregroundColor(AppColors.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                        .background(AppColors.substrateSecondary)
                                        .cornerRadius(12)
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        // Type
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Type")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textSecondary)
                            
                            if isEditing {
                                Picker("Type", selection: $selectedType) {
                                    ForEach(MemoryType.allCases, id: \.self) { type in
                                        Text(type.displayName).tag(type)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            } else {
                                HStack {
                                    Image(systemName: memory.type.icon)
                                    Text(memory.type.displayName)
                                }
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppColors.substrateSecondary)
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Confidence
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Confidence")
                                    .font(AppTypography.labelMedium())
                                    .foregroundColor(AppColors.textSecondary)
                                
                                Spacer()
                                
                                Text("\(Int((isEditing ? confidence : memory.confidence) * 100))%")
                                    .font(AppTypography.labelMedium())
                                    .foregroundColor(AppColors.textPrimary)
                            }
                            
                            if isEditing {
                                Slider(value: $confidence, in: 0...1)
                                    .accentColor(AppColors.signalMercury)
                            } else {
                                ProgressView(value: memory.confidence)
                                    .tint(AppColors.signalMercury)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Tags
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textSecondary)
                            
                            if isEditing {
                                TextField("Tags (comma separated)", text: $tags)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                                    .padding()
                                    .background(AppColors.substrateTertiary)
                                    .cornerRadius(8)
                            } else {
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
                                } else {
                                    Text("No tags")
                                        .font(AppTypography.bodyMedium())
                                        .foregroundColor(AppColors.textTertiary)
                                        .italic()
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Actions
                        if !isEditing {
                            VStack(spacing: 16) {
                                Button(action: toggleArchive) {
                                    HStack {
                                        Image(systemName: memory.isArchived ? "arrow.uturn.backward" : "archivebox")
                                        Text(memory.isArchived ? "Unarchive Memory" : "Archive Memory")
                                    }
                                    .font(AppTypography.labelMedium())
                                    .foregroundColor(AppColors.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(AppColors.substrateSecondary)
                                    .cornerRadius(12)
                                }
                                
                                Button(action: { showingDeleteConfirmation = true }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Delete Memory")
                                    }
                                    .font(AppTypography.labelMedium())
                                    .foregroundColor(AppColors.signalHematite)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(AppColors.signalHematite.opacity(0.1))
                                    .cornerRadius(12)
                                }
                            }
                            .padding()
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Memory Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditing {
                        Button("Cancel") {
                            // Reset values
                            content = memory.content
                            selectedType = memory.type
                            confidence = memory.confidence
                            tags = memory.tags.joined(separator: ", ")
                            context = memory.context ?? ""
                            isEditing = false
                        }
                        .foregroundColor(AppColors.textSecondary)
                    } else {
                        Button("Close") {
                            dismiss()
                        }
                        .foregroundColor(AppColors.textSecondary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Edit") {
                        if isEditing {
                            saveChanges()
                        } else {
                            isEditing = true
                        }
                    }
                    .foregroundColor(AppColors.signalMercury)
                }
            }
            .alert("Delete Memory?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteMemory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }
    
    private func saveChanges() {
        Task {
            do {
                let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                
                _ = try await memoryService.updateMemory(
                    id: memory.id,
                    content: content,
                    confidence: confidence,
                    tags: tagList,
                    context: context.isEmpty ? nil : context
                )
                isEditing = false
            } catch {
                print("Error updating memory: \(error.localizedDescription)")
            }
        }
    }
    
    private func toggleArchive() {
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
    
    private func deleteMemory() {
        Task {
            do {
                try await memoryService.deleteMemory(id: memory.id)
                dismiss()
            } catch {
                print("Error deleting memory: \(error.localizedDescription)")
            }
        }
    }
}

