//
//  WorkspaceRow.swift
//  Axon
//
//  Row view for displaying a workspace in the list.
//

import SwiftUI

struct WorkspaceRow: View {
    let workspace: Workspace

    @StateObject private var workspaceService = WorkspaceService.shared

    var body: some View {
        GlassCard(padding: 16) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(workspaceColor.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: workspace.iconName ?? "folder.fill")
                        .font(.system(size: 20))
                        .foregroundColor(workspaceColor)
                }

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(workspace.name)
                        .font(AppTypography.bodyMedium(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    if let description = workspace.description, !description.isEmpty {
                        Text(description)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(2)
                    }

                    // Stats row
                    HStack(spacing: 12) {
                        if !workspace.associatedTags.isEmpty {
                            Label("\(workspace.associatedTags.count)", systemImage: "tag.fill")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.signalMercury)
                        }

                        if !workspace.conversationIds.isEmpty {
                            Label("\(workspace.conversationIds.count)", systemImage: "bubble.left.fill")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }

                        let memoryCount = workspaceService.memories(for: workspace).count
                        if memoryCount > 0 {
                            Label("\(memoryCount)", systemImage: "brain.fill")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }

                    // Tags preview
                    if !workspace.associatedTags.isEmpty {
                        Text(workspace.associatedTags.prefix(4).map { "#\($0)" }.joined(separator: " "))
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.signalMercury)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
    }

    private var workspaceColor: Color {
        if let hex = workspace.colorHex {
            return Color(hex: hex)
        }
        return AppColors.signalMercury
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        WorkspaceRow(workspace: Workspace(
            name: "AI Research",
            description: "Notes and conversations about AI safety and alignment",
            associatedTags: ["ai", "research", "safety", "alignment"],
            iconName: "brain.fill",
            colorHex: "#9B5DE5"
        ))

        WorkspaceRow(workspace: Workspace(
            name: "App Development",
            description: "Axon iOS development work",
            associatedTags: ["swift", "ios", "development"],
            iconName: "hammer.fill",
            colorHex: "#2A9D8F",
            conversationIds: ["1", "2", "3"]
        ))

        WorkspaceRow(workspace: Workspace(
            name: "Personal",
            associatedTags: ["personal", "notes"],
            iconName: "heart.fill",
            colorHex: "#F15BB5"
        ))
    }
    .padding()
    .background(AppColors.substratePrimary)
}
