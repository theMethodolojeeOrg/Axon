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
        GeometryReader { proxy in
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
                .frame(width: min(360, proxy.size.width * 0.82))
                .background(AppColors.substrateSecondary.opacity(0.95))
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 18,
                        topTrailingRadius: 18
                    )
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 18,
                        topTrailingRadius: 18
                    )
                    .stroke(AppColors.glassBorder.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: AppColors.shadowStrong.opacity(0.75), radius: 18, x: 6, y: 0)

                Spacer()
            }
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
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    #if os(macOS)
                    ToolbarItem {
                        Button("Cancel") { showingRenameSheet = false }
                            .foregroundColor(AppColors.textSecondary)
                    }
                    ToolbarItem {
                        Button("Save") {
                            if let conv = renamingConversation {
                                let trimmed = tempRenameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                SettingsStorage.shared.setDisplayName(trimmed.isEmpty ? nil : trimmed, for: conv.id)
                            }
                            showingRenameSheet = false
                        }
                        .foregroundColor(AppColors.signalMercury)
                    }
                    #else
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
                    #endif
                }
            }
        }
        .alert("Delete Conversation", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                deletingConversation = nil
            }
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
                Text("Are you sure you want to delete '\(SettingsStorage.shared.displayName(for: conversation.id) ?? conversation.title)'? This action cannot be undone.")
            }
        }
        .alert("Error Deleting Conversation", isPresented: .constant(deleteError != nil)) {
            Button("OK") {
                deleteError = nil
            }
        } message: {
            if let error = deleteError {
                Text(error)
            }
        }
        .alert("Sync Error", isPresented: $showingSyncError) {
            Button("OK") {
                syncErrorMessage = nil
            }
            Button("Retry") {
                Task {
                    await forceFullSync()
                }
            }
        } message: {
            if let error = syncErrorMessage {
                Text("Failed to sync conversations: \(error)")
            }
        }
        .sheet(isPresented: $showingWorkspaces) {
            WorkspacesView()
        }
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Axon")
                        .font(AppTypography.titleLarge())
                        .foregroundColor(AppColors.textPrimary)

                    HStack(spacing: 8) {
                        if let displayName = authService.displayName {
                            Text(displayName)
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        // Sync indicator
                        if syncManager.isSyncing {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 12, height: 12)
                                Text("Syncing...")
                                    .font(AppTypography.labelSmall())
                            }
                            .foregroundColor(AppColors.textTertiary)
                        } else if let lastSync = syncManager.lastSyncTime {
                            Text("Updated \(lastSync, style: .relative)")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                }

                Spacer()

                Button {
                    withAnimation {
                        isPresented = false
                    }
                } label: {
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

            // Workspaces button
            Button(action: {
                showingWorkspaces = true
            }) {
                HStack {
                    Image(systemName: "folder.fill")
                    Text("Workspaces")
                        .font(AppTypography.bodyMedium(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppColors.substrateSecondary)
                .foregroundColor(AppColors.textPrimary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
            }
            
            // Create Gallery button
            Button(action: {
                onNavigate(.create)
            }) {
                HStack {
                    Image(systemName: "paintpalette.fill")
                    Text("Create")
                        .font(AppTypography.bodyMedium(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(currentView == .create ? AppColors.signalMercury.opacity(0.15) : AppColors.substrateSecondary)
                .foregroundColor(currentView == .create ? AppColors.signalMercury : AppColors.textPrimary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(currentView == .create ? AppColors.signalMercury.opacity(0.3) : AppColors.glassBorder, lineWidth: 1)
                )
            }
        }
        .padding()
        .background(AppColors.substratePrimary)
    }

    // MARK: - Conversations Section

    /// Sorted conversations: pinned first (in pin order), then unpinned by recency
    private var sortedConversations: [Conversation] {
        let nonArchived = conversationService.conversations.filter { !SettingsStorage.shared.isConversationArchived($0.id) }
        let pinnedIds = SettingsStorage.shared.pinnedConversationIds()

        // Separate pinned and unpinned
        let pinned = pinnedIds.compactMap { id in nonArchived.first { $0.id == id } }
        let unpinned = nonArchived.filter { !pinnedIds.contains($0.id) }

        // Sort unpinned by most recent interaction (lastMessageAt or updatedAt)
        let sortedUnpinned = unpinned.sorted { lhs, rhs in
            let lhsDate = lhs.lastMessageAt ?? lhs.updatedAt
            let rhsDate = rhs.lastMessageAt ?? rhs.updatedAt
            return lhsDate > rhsDate
        }

        return pinned + sortedUnpinned
    }

    private var conversationsSection: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if conversationService.conversations.isEmpty {
                    emptyConversationsView
                } else {
                    ForEach(sortedConversations) { conversation in
                        let isPinned = SettingsStorage.shared.isConversationPinned(conversation.id)
                        ConversationSidebarRow(
                            conversation: conversation,
                            isSelected: selectedConversation?.id == conversation.id && currentView == .chat,
                            displayNameOverride: SettingsStorage.shared.displayName(for: conversation.id),
                            isPinned: isPinned
                        ) {
                            onSelectConversation(conversation)
                        }
                        .contextMenu {
                            // Pin/Unpin toggle
                            Button {
                                SettingsStorage.shared.togglePinConversation(id: conversation.id)
                            } label: {
                                if SettingsStorage.shared.isConversationPinned(conversation.id) {
                                    Label("Unpin", systemImage: "pin.slash")
                                } else {
                                    Label("Pin to Top", systemImage: "pin")
                                }
                            }

                            Divider()

                            Button {
                                renamingConversation = conversation
                                tempRenameTitle = SettingsStorage.shared.displayName(for: conversation.id) ?? conversation.title
                                showingRenameSheet = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button {
                                Task {
                                    do {
                                        // Archive on server (soft delete)
                                        try await conversationService.deleteConversation(id: conversation.id, hardDelete: false)
                                        // Add to local archive storage for UI filtering
                                        SettingsStorage.shared.archiveConversation(id: conversation.id)
                                    } catch {
                                        print("Archive failed: \(error)")
                                    }
                                }
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }

                            Divider()

                            Button(role: .destructive) {
                                deletingConversation = conversation
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
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
            // Pull-to-refresh: Force full sync from API
            let retention = SettingsStorage.shared.loadSettings()?.archiveRetentionDays ?? 30
            SettingsStorage.shared.purgeExpiredArchived(retentionDays: retention)
            await forceFullSync()
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
                    icon: "brain.head.profile",
                    title: "Cognition",
                    isSelected: currentView == .cognition
                ) {
                    onNavigate(.cognition)
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

    private func forceFullSync() async {
        do {
            let provider = SettingsViewModel.shared.settings.deviceModeConfig.cloudSyncProvider

            if provider == .iCloud {
                print("[SidebarView] Starting iCloud pull...")
                await AutoSyncOrchestrator.shared.pullNow()
                conversationService.conversations = syncManager.loadLocalConversations()
                print("[SidebarView] ✅ iCloud pull completed. Loaded \(conversationService.conversations.count) conversations")
                return
            }

            // Default: backend/API sync
            print("[SidebarView] Starting force full sync...")
            // Force full sync with listAll=true, overwriting everything
            try await syncManager.forceFullSync()
            // Reload conversations after sync completes
            conversationService.conversations = syncManager.loadLocalConversations()
            print("[SidebarView] ✅ Force full sync completed. Loaded \(conversationService.conversations.count) conversations")
        } catch {
            print("[SidebarView] ❌ Error forcing full sync: \(error.localizedDescription)")
            syncErrorMessage = error.localizedDescription
            showingSyncError = true
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
            .frame(minHeight: ChatVisualTokens.minTouchTarget)
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
    var isPinned: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon - pin for pinned, bubble for regular
                Image(systemName: isPinned ? "pin.fill" : "bubble.left.fill")
                    .font(.system(size: isPinned ? 14 : 16))
                    .foregroundColor(isPinned ? .white : (isSelected ? AppColors.signalMercury : AppColors.textTertiary))
                    .frame(width: 28, height: 28)
                    .background(
                        isPinned ?
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppColors.signalMercury) :
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.clear)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayNameOverride ?? conversation.title)
                        .font(isPinned ? AppTypography.bodyMedium(.semibold) : AppTypography.bodyMedium(.medium))
                        .foregroundColor(isPinned ? AppColors.textPrimary : AppColors.textPrimary)
                        .lineLimit(1)

                    if let lastMessage = conversation.lastMessage {
                        Text(lastMessage)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let lastMessageAt = conversation.lastMessageAt {
                        Text(lastMessageAt, style: .relative)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(isPinned ? AppColors.signalMercury : AppColors.textTertiary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.15) :
                          (isPinned ? AppColors.signalMercury.opacity(0.08) : Color.clear))
            )
            .overlay(
                isPinned ?
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.signalMercury.opacity(0.2), lineWidth: 1) :
                    nil
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
