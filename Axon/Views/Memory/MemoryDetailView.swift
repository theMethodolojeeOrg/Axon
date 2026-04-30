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
    @StateObject private var learningService = LearningLoopService.shared

    let memory: Memory

    @State private var content: String
    @State private var selectedType: MemoryType
    @State private var confidence: Double
    @State private var tags: String
    @State private var context: String
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false

    /// Get learning data for this memory
    private var learningData: MemoryLearningData? {
        learningService.learningData[memory.id]
    }

    /// Get refinement suggestions
    private var refinementSuggestions: [RefinementSuggestion] {
        learningService.getRefinementSuggestions(for: memory.id)
    }

    init(memory: Memory) {
        self.memory = memory
        _content = State(initialValue: memory.content)
        _selectedType = State(initialValue: memory.type)
        _confidence = State(initialValue: memory.confidence)
        _tags = State(initialValue: memory.tags.joined(separator: ", "))
        _context = State(initialValue: memory.context ?? "")
    }
    
    var body: some View {
        #if os(macOS)
        ZStack {
            AppSurfaces.color(.contentBackground)
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
                                .background(AppSurfaces.color(.controlBackground))
                                .cornerRadius(8)
                        } else {
                            Text(memory.content)
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(AppSurfaces.color(.cardBackground))
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
                                    .background(AppSurfaces.color(.controlBackground))
                                    .cornerRadius(8)
                            } else {
                                Text(context)
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .background(AppSurfaces.color(.cardBackground))
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
                                ForEach(MemoryType.selectableCases, id: \.self) { type in
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
                            .background(AppSurfaces.color(.cardBackground))
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
                                .background(AppSurfaces.color(.controlBackground))
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

                    // Learning Stats (if available)
                    if let learning = learningData, !isEditing {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Learning Stats")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textSecondary)

                            HStack(spacing: 16) {
                                // Reliability indicator
                                VStack(spacing: 4) {
                                    Text("\(Int(learning.reliability * 100))%")
                                        .font(AppTypography.titleMedium())
                                        .foregroundColor(learning.reliability >= 0.7 ? AppColors.accentSuccess : AppColors.signalHematite)
                                    Text("Reliability")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.textTertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppSurfaces.color(.cardBackground))
                                .cornerRadius(8)

                                // Success/Failure counts
                                VStack(spacing: 4) {
                                    HStack(spacing: 8) {
                                        Label("\(learning.successCount)", systemImage: "checkmark.circle.fill")
                                            .foregroundColor(AppColors.accentSuccess)
                                        Label("\(learning.failureCount)", systemImage: "xmark.circle.fill")
                                            .foregroundColor(AppColors.signalHematite)
                                    }
                                    .font(AppTypography.bodyMedium())
                                    Text("Predictions")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.textTertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppSurfaces.color(.cardBackground))
                                .cornerRadius(8)
                            }

                            // Refinement suggestions
                            if !refinementSuggestions.isEmpty {
                                ForEach(refinementSuggestions, id: \.reason) { suggestion in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: suggestionIcon(for: suggestion.type))
                                            .foregroundColor(suggestionColor(for: suggestion.type))
                                            .font(.system(size: 14))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.reason)
                                                .font(AppTypography.labelSmall())
                                                .foregroundColor(AppColors.textSecondary)
                                            Text(suggestion.suggestedAction)
                                                .font(AppTypography.labelSmall())
                                                .foregroundColor(AppColors.textTertiary)
                                        }
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(suggestionColor(for: suggestion.type).opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

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
                                .background(AppSurfaces.color(.cardBackground))
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
        .toolbar {
            #if os(macOS)
            ToolbarItem {
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

            ToolbarItem {
                Button(isEditing ? "Save" : "Edit") {
                    if isEditing {
                        saveChanges()
                    } else {
                        isEditing = true
                    }
                }
                .foregroundColor(AppColors.signalMercury)
            }
            #else
            // This else will be ignored on macOS
            #endif
        }
        .alert("Delete Memory?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteMemory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 500, idealHeight: 600)
        #else
        NavigationView {
            ZStack {
                AppSurfaces.color(.contentBackground)
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
                                    .background(AppSurfaces.color(.controlBackground))
                                    .cornerRadius(8)
                            } else {
                                Text(memory.content)
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .background(AppSurfaces.color(.cardBackground))
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
                                        .background(AppSurfaces.color(.controlBackground))
                                        .cornerRadius(8)
                                } else {
                                    Text(context)
                                        .font(AppTypography.bodyMedium())
                                        .foregroundColor(AppColors.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                        .background(AppSurfaces.color(.cardBackground))
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
                                    ForEach(MemoryType.selectableCases, id: \.self) { type in
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
                                .background(AppSurfaces.color(.cardBackground))
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
                                    .background(AppSurfaces.color(.controlBackground))
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

                        // Learning Stats (if available)
                        if let learning = learningData, !isEditing {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Learning Stats")
                                    .font(AppTypography.labelMedium())
                                    .foregroundColor(AppColors.textSecondary)

                                HStack(spacing: 16) {
                                    // Reliability indicator
                                    VStack(spacing: 4) {
                                        Text("\(Int(learning.reliability * 100))%")
                                            .font(AppTypography.titleMedium())
                                            .foregroundColor(learning.reliability >= 0.7 ? AppColors.accentSuccess : AppColors.signalHematite)
                                        Text("Reliability")
                                            .font(AppTypography.labelSmall())
                                            .foregroundColor(AppColors.textTertiary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(AppSurfaces.color(.cardBackground))
                                    .cornerRadius(8)

                                    // Success/Failure counts
                                    VStack(spacing: 4) {
                                        HStack(spacing: 8) {
                                            Label("\(learning.successCount)", systemImage: "checkmark.circle.fill")
                                                .foregroundColor(AppColors.accentSuccess)
                                            Label("\(learning.failureCount)", systemImage: "xmark.circle.fill")
                                                .foregroundColor(AppColors.signalHematite)
                                        }
                                        .font(AppTypography.bodyMedium())
                                        Text("Predictions")
                                            .font(AppTypography.labelSmall())
                                            .foregroundColor(AppColors.textTertiary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(AppSurfaces.color(.cardBackground))
                                    .cornerRadius(8)
                                }

                                // Refinement suggestions
                                if !refinementSuggestions.isEmpty {
                                    ForEach(refinementSuggestions, id: \.reason) { suggestion in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: suggestionIcon(for: suggestion.type))
                                                .foregroundColor(suggestionColor(for: suggestion.type))
                                                .font(.system(size: 14))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(suggestion.reason)
                                                    .font(AppTypography.labelSmall())
                                                    .foregroundColor(AppColors.textSecondary)
                                                Text(suggestion.suggestedAction)
                                                    .font(AppTypography.labelSmall())
                                                    .foregroundColor(AppColors.textTertiary)
                                            }
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(suggestionColor(for: suggestion.type).opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

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
                                    .background(AppSurfaces.color(.cardBackground))
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
        }
        .alert("Delete Memory?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteMemory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        #endif
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

    // MARK: - Refinement Suggestion Helpers

    private func suggestionIcon(for type: RefinementType) -> String {
        switch type {
        case .reduceConfidence:
            return "arrow.down.circle"
        case .increaseConfidence:
            return "arrow.up.circle"
        case .addConditions:
            return "plus.circle"
        case .split:
            return "arrow.triangle.branch"
        case .archive:
            return "archivebox"
        }
    }

    private func suggestionColor(for type: RefinementType) -> Color {
        switch type {
        case .reduceConfidence:
            return AppColors.signalHematite
        case .increaseConfidence:
            return AppColors.accentSuccess
        case .addConditions:
            return AppColors.signalMercury
        case .split:
            return AppColors.signalCopper
        case .archive:
            return AppColors.textTertiary
        }
    }
}
