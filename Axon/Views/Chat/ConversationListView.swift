//
//  ConversationListView.swift
//  Axon
//
//  List of conversations/threads
//

import SwiftUI

struct ConversationListView: View {
    @StateObject private var conversationService = ConversationService.shared
    @State private var showNewConversation = false
    @State private var newConversationTitle = ""

    var body: some View {
        NavigationView {
            ZStack {
                AppColors.substratePrimary
                    .ignoresSafeArea()

                if conversationService.conversations.isEmpty && !conversationService.isLoading {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 60))
                            .foregroundColor(AppColors.signalMercury.opacity(0.5))

                        Text("No Conversations Yet")
                            .font(AppTypography.headlineSmall())
                            .foregroundColor(AppColors.textPrimary)

                        Text("Start a new conversation to begin chatting")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)

                        Button(action: { showNewConversation = true }) {
                            HStack {
                                Image(systemName: "plus")
                                Text("New Conversation")
                            }
                            .font(AppTypography.titleMedium())
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(AppColors.signalMercury)
                            .cornerRadius(12)
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(conversationService.conversations) { conversation in
                                NavigationLink(destination: ChatContainerView(
                                    conversation: conversation,
                                    onNewChat: {},
                                    onConversationCreated: { _ in }
                                )) {
                                    ConversationRow(conversation: conversation)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                }

                if conversationService.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.signalMercury))
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                #if os(macOS)
                ToolbarItem {
                    Button(action: { showNewConversation = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(AppColors.signalMercury)
                    }
                }
                #else
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showNewConversation = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(AppColors.signalMercury)
                    }
                }
                #endif
            }
            .sheet(isPresented: $showNewConversation) {
                NewConversationSheet(
                    title: $newConversationTitle,
                    onCreate: createConversation
                )
            }
            .task {
                await loadConversations()
            }
            .refreshable {
                await loadConversations()
            }
        }
    }

    private func loadConversations() async {
        do {
            try await conversationService.listConversations()
        } catch {
            print("Error loading conversations: \(error.localizedDescription)")
        }
    }

    private func createConversation() {
        guard !newConversationTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        Task {
            do {
                _ = try await conversationService.createConversation(title: newConversationTitle)
                newConversationTitle = ""
                showNewConversation = false
            } catch {
                print("Error creating conversation: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(conversation.title)
                        .font(AppTypography.titleMedium())
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    if let lastMessageAt = conversation.lastMessageAt {
                        Text(lastMessageAt, style: .relative)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                if let lastMessage = conversation.lastMessage {
                    Text(lastMessage)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }

                HStack {
                    Label("\(conversation.messageCount)", systemImage: "bubble.left.and.bubble.right")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    Spacer()

                    if conversation.isPinned ?? false {
                        Image(systemName: "pin.fill")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.signalCopper)
                    }
                }
            }
        }
    }
}

// MARK: - New Conversation Sheet

struct NewConversationSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var title: String
    let onCreate: () -> Void

    var body: some View {
        NavigationView {
            ZStack {
                AppColors.substratePrimary
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Conversation Title")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        TextField("Enter a title", text: $title)
                            .textFieldStyle(AppTextFieldStyle())
                    }

                    Button(action: {
                        onCreate()
                    }) {
                        Text("Create Conversation")
                            .font(AppTypography.titleMedium())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppColors.signalMercury)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("New Conversation")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.textSecondary)
                }
                #else
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.textSecondary)
                }
                #endif
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ConversationListView()
}
