//
//  MessageEditSheet.swift
//  Axon
//
//  Sheet for editing a user message with options to save or save & regenerate
//

import SwiftUI

struct MessageEditSheet: View {
    let message: Message
    let onSave: (String) -> Void
    let onSaveAndRegenerate: (String) -> Void
    let onCancel: () -> Void
    
    @State private var editedContent: String = ""
    @State private var showHistory = false
    @FocusState private var isTextEditorFocused: Bool
    
    var body: some View {
        #if os(macOS)
        // macOS: Direct content without NavigationView to avoid sidebar-like behavior
        sheetContent
            .frame(minWidth: 500, idealWidth: 600, minHeight: 400, idealHeight: 500)
            .onAppear {
                editedContent = message.content
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isTextEditorFocused = true
                }
            }
        #else
        // iOS: Keep NavigationView for proper navigation
        NavigationView {
            sheetContent
                .navigationTitle("Edit Message")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            onCancel()
                        }
                    }
                }
        }
        .onAppear {
            editedContent = message.content
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextEditorFocused = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var sheetContent: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            // macOS header with title and cancel button
            HStack {
                Text("Edit Message")
                    .font(AppTypography.titleMedium())
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .foregroundColor(AppColors.textSecondary)
            }
            .padding()

            Divider()
            #endif

            // Edit history disclosure (if message has been edited before)
            if message.isEdited, let history = message.editHistory, !history.isEmpty {
                Button {
                    showHistory.toggle()
                } label: {
                    HStack {
                        Image(systemName: showHistory ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12))
                        Text("View \(history.count) previous version\(history.count == 1 ? "" : "s")")
                            .font(AppTypography.labelSmall())
                        Spacer()
                    }
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                if showHistory {
                    EditHistoryView(
                        editHistory: history,
                        currentVersion: message.currentVersion ?? 0,
                        onSelectVersion: { version in
                            // Load selected version content into editor
                            if let historyItem = history.first(where: { $0.version == version }) {
                                editedContent = historyItem.content
                            }
                        }
                    )
                    .padding(.bottom, 8)
                }

                Divider()
            }

            // Text editor for editing message content
            TextEditor(text: $editedContent)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)
                .scrollContentBackground(.hidden)
                .background(AppColors.substratePrimary)
                .focused($isTextEditorFocused)
                .padding()

            Divider()

            // Action buttons
            VStack(spacing: 12) {
                // Save & Regenerate - primary action
                Button {
                    onSaveAndRegenerate(editedContent)
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Save & Regenerate")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColors.signalLichen)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                // Save only - secondary action
                Button {
                    onSave(editedContent)
                } label: {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Save Only")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColors.substrateSecondary)
                    .foregroundColor(AppColors.textPrimary)
                    .cornerRadius(10)
                }
                .disabled(editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .background(AppColors.substratePrimary)
    }
}

// MARK: - Edit History View

struct EditHistoryView: View {
    let editHistory: [MessageEdit]
    let currentVersion: Int
    let onSelectVersion: (Int) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(editHistory.sorted(by: { $0.version > $1.version })) { edit in
                    Button {
                        onSelectVersion(edit.version)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("v\(edit.version)")
                                    .font(AppTypography.labelSmall())
                                    .fontWeight(.semibold)
                                if edit.version == currentVersion - 1 {
                                    Text("Previous")
                                        .font(.system(size: 9))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(AppColors.signalLichen.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                            Text(edit.timestamp, style: .time)
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textTertiary)
                            Text(edit.content.prefix(50) + (edit.content.count > 50 ? "..." : ""))
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(2)
                        }
                        .padding(8)
                        .frame(width: 140)
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

#if DEBUG
struct MessageEditSheet_Previews: PreviewProvider {
    static var previews: some View {
        MessageEditSheet(
            message: Message(
                conversationId: "test",
                role: .user,
                content: "This is a test message that I want to edit.",
                editHistory: [
                    MessageEdit(content: "Original content", version: 0)
                ],
                currentVersion: 1
            ),
            onSave: { _ in },
            onSaveAndRegenerate: { _ in },
            onCancel: {}
        )
    }
}
#endif
