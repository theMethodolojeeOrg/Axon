//
//  MacSidebarContentView.swift
//  Axon
//
//  Native macOS sidebar content used within NavigationSplitView.
//

import SwiftUI

#if os(macOS)

struct MacSidebarContentView: View {
    @Binding var selectedConversation: Conversation?
    @Binding var currentView: MainView

    let onSelectConversation: (Conversation) -> Void
    let onNewChat: () -> Void
    let onNavigate: (MainView) -> Void

    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var syncManager = ConversationSyncManager.shared

    @State private var renamingConversation: Conversation? = nil
    @State private var tempRenameTitle: String = ""
    @State private var showingRenameSheet: Bool = false
    @State private var showingDeleteAlert: Bool = false
    @State private var deletingConversation: Conversation? = nil
    @State private var deleteError: String? = nil
    @State private var syncErrorMessage: String? = nil
    @State private var showingSyncError: Bool = false
    @State private var showingWorkspaces: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().background(AppColors.divider)

            // Always show conversations - they're accessible from any view
            conversationsSection

            Spacer(minLength: 0)

            Divider().background(AppColors.divider)

            bottomNavigation
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.substrateSecondary)
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
        .alert("Delete Conversation", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { deletingConversation = nil }
            Button("Delete", role: .destructive) {
                if let conversation = deletingConversation {
                    Task { @MainActor in
                        do {
                            try await conversationService.deleteConversation(id: conversation.id, hardDelete: true)
                            deletingConversation = nil
                        } catch {
                            deleteError = error.localizedDescription
                            deletingConversation = nil
                        }
                    }
                }
            }
        } message: {
            if let conversation = deletingConversation {
                let resolvedTitle = SettingsStorage.shared.resolvedConversationTitle(
                    conversationId: conversation.id,
                    persistedTitle: conversation.title
                )
                Text("Are you sure you want to delete '\(resolvedTitle)'? This action cannot be undone.")
            }
        }
        .alert("Error Deleting Conversation", isPresented: .constant(deleteError != nil)) {
            Button("OK") { deleteError = nil }
        } message: {
            if let error = deleteError {
                Text(error)
            }
        }
        .alert("Sync Error", isPresented: $showingSyncError) {
            Button("OK") { syncErrorMessage = nil }
            Button("Retry") { Task { await forceFullSync() } }
        } message: {
            if let error = syncErrorMessage {
                Text("Failed to sync conversations: \(error)")
            }
        }
        .sheet(isPresented: $showingWorkspaces) {
            WorkspacesView()
        }
        .task {
            let retention = SettingsStorage.shared.loadSettings()?.archiveRetentionDays ?? 30
            SettingsStorage.shared.purgeExpiredArchived(retentionDays: retention)
            await loadConversations()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Axon")
                        .font(AppTypography.titleLarge())
                        .foregroundColor(AppColors.textPrimary)

                    if let displayName = authService.displayName {
                        Text(displayName)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                Spacer()

                // Sync indicator
                if syncManager.isSyncing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                }
            }

            if syncManager.isSyncing {
                Text("Syncing…")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            } else if let lastSync = syncManager.lastSyncTime {
                Text("Updated \(lastSync, style: .relative)")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            // New chat button
            Button(action: onNewChat) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                    Text("New Chat")
                        .font(AppTypography.bodyMedium(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.signalMercury)

            // Workspaces button
            Button(action: {
                showingWorkspaces = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                    Text("Workspaces")
                        .font(AppTypography.bodyMedium(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(AppColors.textSecondary)
        }
        .padding(12)
        .background(AppColors.substratePrimary)
    }

    // MARK: - Conversations

    private var conversationsSection: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if conversationService.conversations.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 34))
                            .foregroundColor(AppColors.textTertiary)

                        Text("No conversations yet")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(conversationService.conversations.filter { !SettingsStorage.shared.isConversationArchived($0.id) }) { conversation in
                        ConversationSidebarRow(
                            conversation: conversation,
                            isSelected: selectedConversation?.id == conversation.id && currentView == .chat,
                            displayNameOverride: SettingsStorage.shared.resolvedConversationTitle(
                                conversationId: conversation.id,
                                persistedTitle: conversation.title
                            )
                        ) {
                            onSelectConversation(conversation)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                deletingConversation = conversation
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                Task {
                                    do {
                                        try await conversationService.deleteConversation(id: conversation.id, hardDelete: false)
                                        SettingsStorage.shared.archiveConversation(id: conversation.id)
                                    } catch {
                                        print("Archive failed: \(error)")
                                    }
                                }
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }

                            Button {
                                renamingConversation = conversation
                                tempRenameTitle = SettingsStorage.shared.resolvedConversationTitle(
                                    conversationId: conversation.id,
                                    persistedTitle: conversation.title
                                )
                                showingRenameSheet = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .refreshable {
            let retention = SettingsStorage.shared.loadSettings()?.archiveRetentionDays ?? 30
            SettingsStorage.shared.purgeExpiredArchived(retentionDays: retention)
            await forceFullSync()
        }
    }

    // MARK: - Bottom nav

    private var bottomNavigation: some View {
        VStack(spacing: 8) {
            Button {
                onNavigate(.chat)
            } label: {
                Label("Chats", systemImage: currentView == .chat ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(currentView == .chat ? AppColors.signalMercury.opacity(0.12) : Color.clear)
            .cornerRadius(8)

            Button {
                onNavigate(.cognition)
            } label: {
                Label("Cognition", systemImage: currentView == .cognition ? "brain.head.profile.fill" : "brain.head.profile")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(currentView == .cognition ? AppColors.signalMercury.opacity(0.12) : Color.clear)
            .cornerRadius(8)

            Button {
                onNavigate(.settings)
            } label: {
                Label("Settings", systemImage: currentView == .settings ? "gearshape.fill" : "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(currentView == .settings ? AppColors.signalMercury.opacity(0.12) : Color.clear)
            .cornerRadius(8)
        }
        .padding(10)
        .background(AppColors.substratePrimary)
    }

    // MARK: - Actions

    private func loadConversations() async {
        do {
            try await conversationService.listConversations()
        } catch {
            print("Error loading conversations: \(error.localizedDescription)")
        }
    }

    private func forceFullSync() async {
        do {
            print("[MacSidebarContentView] Starting force full sync...")
            try await syncManager.forceFullSync()
            conversationService.conversations = syncManager.loadLocalConversations()
            print("[MacSidebarContentView] ✅ Force full sync completed. Loaded \(conversationService.conversations.count) conversations")
        } catch {
            print("[MacSidebarContentView] ❌ Error forcing full sync: \(error.localizedDescription)")
            syncErrorMessage = error.localizedDescription
            showingSyncError = true
        }
    }
}

#Preview {
    MacSidebarContentView(
        selectedConversation: .constant(nil),
        currentView: .constant(.chat),
        onSelectConversation: { _ in },
        onNewChat: {},
        onNavigate: { _ in }
    )
    .frame(width: 300)
}

#endif
