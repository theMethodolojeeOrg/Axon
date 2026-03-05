//
//  WorkspaceDetailView.swift
//  Axon
//
//  Detail view for a workspace showing associated threads, memories, and settings.
//

import SwiftUI

struct WorkspaceDetailView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var viewModel: WorkspaceViewModel

    let workspace: Workspace

    @State private var selectedTab: WorkspaceDetailTab = .threads
    @StateObject private var workspaceService = WorkspaceService.shared
    @StateObject private var conversationService = ConversationService.shared

    enum WorkspaceDetailTab: String, CaseIterable, Identifiable {
        case threads = "Threads"
        case memories = "Memories"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .threads: return "bubble.left.fill"
            case .memories: return "brain.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppColors.substratePrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Workspace header
                    workspaceHeader

                    // Tab selector
                    tabSelector

                    Divider()
                        .background(AppColors.divider)

                    // Tab content
                    switch selectedTab {
                    case .threads:
                        threadsContent
                    case .memories:
                        memoriesContent
                    case .settings:
                        settingsContent
                    }
                }
            }
            .navigationTitle(workspace.name)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppColors.signalMercury)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.startEditing(workspace)
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var workspaceHeader: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(workspaceColor.opacity(0.2))
                    .frame(width: 56, height: 56)

                Image(systemName: workspace.iconName ?? "folder.fill")
                    .font(.system(size: 24))
                    .foregroundColor(workspaceColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(workspace.name)
                    .font(AppTypography.titleMedium())
                    .foregroundColor(AppColors.textPrimary)

                if let description = workspace.description, !description.isEmpty {
                    Text(description)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }

                // Stats
                HStack(spacing: 16) {
                    Label("\(workspace.associatedTags.count) tags", systemImage: "tag.fill")
                    Label("\(workspace.conversationIds.count) threads", systemImage: "bubble.left.fill")
                    Label("\(workspaceService.memories(for: workspace).count) memories", systemImage: "brain.fill")
                }
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
            }

            Spacer()
        }
        .padding()
        .background(AppColors.substrateSecondary)
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(WorkspaceDetailTab.allCases) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                            Text(tab.rawValue)
                                .font(AppTypography.labelMedium())
                        }
                        .foregroundColor(selectedTab == tab ? AppColors.signalMercury : AppColors.textSecondary)

                        Rectangle()
                            .fill(selectedTab == tab ? AppColors.signalMercury : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Threads Content

    private var threadsContent: some View {
        Group {
            let conversations = workspaceService.conversations(for: workspace)

            if conversations.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40))
                        .foregroundColor(AppColors.textTertiary)

                    Text("No Threads Yet")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textSecondary)

                    Text("Add conversations to this workspace from the chat list.")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(conversations) { conversation in
                            WorkspaceConversationRow(conversation: conversation)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Memories Content

    private var memoriesContent: some View {
        Group {
            let memories = workspaceService.memories(for: workspace)

            if memories.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "brain")
                        .font(.system(size: 40))
                        .foregroundColor(AppColors.textTertiary)

                    Text("No Matching Memories")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textSecondary)

                    Text("Memories with tags matching this workspace will appear here.")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    if !workspace.associatedTags.isEmpty {
                        Text("Associated tags: " + workspace.associatedTags.map { "#\($0)" }.joined(separator: ", "))
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.signalMercury)
                            .padding(.top, 8)
                    }
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(memories) { memory in
                            WorkspaceMemoryRow(memory: memory)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Settings Content

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Associated Tags
                VStack(alignment: .leading, spacing: 12) {
                    Text("ASSOCIATED TAGS")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    if workspace.associatedTags.isEmpty {
                        Text("No tags associated with this workspace.")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(workspace.associatedTags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(AppColors.signalMercury)
                                    .cornerRadius(12)
                            }
                        }
                    }
                }

                Divider()
                    .background(AppColors.divider)

                // Workspace Info
                VStack(alignment: .leading, spacing: 12) {
                    Text("WORKSPACE INFO")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    HStack {
                        Text("Created")
                            .foregroundColor(AppColors.textSecondary)
                        Spacer()
                        Text(workspace.createdAt, style: .date)
                            .foregroundColor(AppColors.textPrimary)
                    }
                    .font(AppTypography.bodySmall())

                    HStack {
                        Text("Last Updated")
                            .foregroundColor(AppColors.textSecondary)
                        Spacer()
                        Text(workspace.updatedAt, style: .relative)
                            .foregroundColor(AppColors.textPrimary)
                    }
                    .font(AppTypography.bodySmall())
                }

                Divider()
                    .background(AppColors.divider)

                // Danger Zone
                VStack(alignment: .leading, spacing: 12) {
                    Text("DANGER ZONE")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.accentError)

                    Button(action: {
                        viewModel.deleteWorkspace(workspace)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Workspace")
                        }
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.accentError)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.accentError, lineWidth: 1)
                        )
                    }
                }
            }
            .padding()
        }
    }

    private var workspaceColor: Color {
        if let hex = workspace.colorHex {
            return Color(hex: hex)
        }
        return AppColors.signalMercury
    }
}

// MARK: - Conversation Row

struct WorkspaceConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 16))
                .foregroundColor(AppColors.textTertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(SettingsStorage.shared.displayName(for: conversation.id) ?? conversation.title)
                    .font(AppTypography.bodyMedium())
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
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.substrateSecondary)
        )
    }
}

// MARK: - Memory Row

struct WorkspaceMemoryRow: View {
    let memory: Memory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: memory.type.icon)
                .font(.system(size: 16))
                .foregroundColor(AppColors.signalMercury)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(memory.type.displayName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Text(memory.createdAt, style: .relative)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }

                Text(memory.content)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(3)

                if !memory.tags.isEmpty {
                    Text(memory.tags.prefix(4).map { "#\($0)" }.joined(separator: " "))
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalMercury)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.substrateSecondary)
        )
    }
}

// MARK: - Preview

#Preview {
    WorkspaceDetailView(workspace: Workspace(
        name: "AI Research",
        description: "Notes and conversations about AI safety",
        associatedTags: ["ai", "research", "safety"],
        iconName: "brain.fill",
        colorHex: "#9B5DE5",
        conversationIds: ["1", "2"]
    ))
    .environmentObject(WorkspaceViewModel.shared)
}
