//
//  SidebarView.swift
//  Axon
//
//  Slide-out sidebar with conversations list and bottom navigation
//

import SwiftUI

struct SidebarView: View {
    @Binding var isPresented: Bool
    @Binding var selectedConversation: Conversation?
    @Binding var currentView: MainView
    let onSelectConversation: (Conversation) -> Void
    let onNewChat: () -> Void
    let onNavigate: (MainView) -> Void

    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var authService = AuthenticationService.shared

    @State private var renamingConversation: Conversation? = nil
    @State private var tempRenameTitle: String = ""
    @State private var showingRenameSheet: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar content
            VStack(spacing: 0) {
                // Header
                sidebarHeader

                Divider()
                    .background(AppColors.divider)

                // Conversations list
                conversationsSection

                Spacer()

                // Bottom navigation
                bottomNavigation
            }
            .frame(width: UIScreen.main.bounds.width * 0.8)
            .background(AppColors.substrateSecondary)
            .shadow(color: AppColors.shadowStrong, radius: 20, x: 5, y: 0)

            Spacer()
        }
        .sheet(isPresented: $showingRenameSheet) {
            NavigationStack {
                ZStack {
                    AppColors.substratePrimary.ignoresSafeArea()
                    VStack(spacing: 16) {
                        TextField("Display name", text: $tempRenameTitle)
                            .textFieldStyle(AppTextFieldStyle())
                            .padding()
                        Spacer()
                    }
                    .padding()
                }
                .navigationTitle("Rename Chat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingRenameSheet = false }
                            .foregroundColor(AppColors.textSecondary)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let conv = renamingConversation {
                                let trimmed = tempRenameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                SettingsStorage.shared.setDisplayName(trimmed.isEmpty ? nil : trimmed, for: conv.id)
                            }
                            showingRenameSheet = false
                        }
                        .foregroundColor(AppColors.signalMercury)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NeurX AxonChat")
                        .font(AppTypography.titleLarge())
                        .foregroundColor(AppColors.textPrimary)

                    if let displayName = authService.displayName {
                        Text(displayName)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                Spacer()

                Button(action: { withAnimation { isPresented = false } }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(AppColors.substrateTertiary)
                        .clipShape(Circle())
                }
            }

            // New chat button
            Button(action: {
                onNewChat()
            }) {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text("New Chat")
                        .font(AppTypography.titleMedium())
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppColors.signalMercury)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(AppColors.substratePrimary)
    }

    // MARK: - Conversations Section

    private var conversationsSection: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if conversationService.conversations.isEmpty {
                    emptyConversationsView
                } else {
                    ForEach(conversationService.conversations.filter { !SettingsStorage.shared.isConversationArchived($0.id) }) { conversation in
                        ConversationSidebarRow(
                            conversation: conversation,
                            isSelected: selectedConversation?.id == conversation.id && currentView == .chat,
                            displayNameOverride: SettingsStorage.shared.displayName(for: conversation.id)
                        ) {
                            onSelectConversation(conversation)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    do { try await conversationService.deleteConversation(id: conversation.id) } catch { print("Delete failed: \(error)") }
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                SettingsStorage.shared.archiveConversation(id: conversation.id)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }

                            Button {
                                renamingConversation = conversation
                                tempRenameTitle = SettingsStorage.shared.displayName(for: conversation.id) ?? conversation.title
                                showingRenameSheet = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .task {
            let retention = SettingsStorage.shared.loadSettings()?.archiveRetentionDays ?? 30
            SettingsStorage.shared.purgeExpiredArchived(retentionDays: retention)
            await loadConversations()
        }
        .refreshable {
            let retention = SettingsStorage.shared.loadSettings()?.archiveRetentionDays ?? 30
            SettingsStorage.shared.purgeExpiredArchived(retentionDays: retention)
            await loadConversations()
        }
    }

    private var emptyConversationsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)

            Text("No conversations yet")
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textSecondary)

            Text("Start a new chat to begin")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(.top, 60)
    }

    // MARK: - Bottom Navigation

    private var bottomNavigation: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppColors.divider)

            HStack(spacing: 0) {
                NavigationButton(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Chats",
                    isSelected: currentView == .chat
                ) {
                    onNavigate(.chat)
                }

                NavigationButton(
                    icon: "brain.fill",
                    title: "Memory",
                    isSelected: currentView == .memory
                ) {
                    onNavigate(.memory)
                }

                NavigationButton(
                    icon: "gearshape.fill",
                    title: "Settings",
                    isSelected: currentView == .settings
                ) {
                    onNavigate(.settings)
                }
            }
            .padding(.vertical, 12)
            .background(AppColors.substratePrimary)
        }
    }

    // MARK: - Actions

    private func loadConversations() async {
        do {
            try await conversationService.listConversations()
        } catch {
            print("Error loading conversations: \(error.localizedDescription)")
        }
    }
}

// MARK: - Navigation Button

struct NavigationButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)

                Text(title)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Conversation Sidebar Row

struct ConversationSidebarRow: View {
    let conversation: Conversation
    let isSelected: Bool
    var displayNameOverride: String? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textTertiary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayNameOverride ?? conversation.title)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    if let lastMessage = conversation.lastMessage {
                        Text(lastMessage)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let lastMessageAt = conversation.lastMessageAt {
                    Text(lastMessageAt, style: .relative)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AppColors.substratePrimary
            .ignoresSafeArea()

        SidebarView(
            isPresented: .constant(true),
            selectedConversation: .constant(nil),
            currentView: .constant(.chat),
            onSelectConversation: { _ in },
            onNewChat: {},
            onNavigate: { _ in }
        )
    }
}
