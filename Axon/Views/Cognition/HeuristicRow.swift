//
//  HeuristicRow.swift
//  Axon
//
//  Row view for displaying a single heuristic in the list.
//

import SwiftUI

struct HeuristicRow: View {
    let heuristic: Heuristic
    let isSelectionMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Selection checkbox
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textTertiary)
            }

            // Type icon
            ZStack {
                Circle()
                    .fill(typeColor.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: heuristic.type.icon)
                    .font(.system(size: 18))
                    .foregroundColor(typeColor)
            }

            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Header: Type + Dimension badges
                HStack(spacing: 8) {
                    // Type badge
                    HStack(spacing: 4) {
                        Image(systemName: heuristic.type.icon)
                            .font(.system(size: 10))
                        Text(heuristic.type.displayName)
                            .font(AppTypography.labelSmall())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(typeColor.opacity(0.15))
                    .foregroundColor(typeColor)
                    .cornerRadius(6)

                    // Dimension badge
                    HStack(spacing: 4) {
                        Image(systemName: heuristic.dimension.icon)
                            .font(.system(size: 10))
                        Text(heuristic.dimension.displayName)
                            .font(AppTypography.labelSmall())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.substrateTertiary)
                    .foregroundColor(AppColors.textSecondary)
                    .cornerRadius(6)

                    Spacer()

                    // Timestamp
                    Text(heuristic.synthesizedAt, style: .relative)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }

                // Content
                Text(heuristic.content)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(4)

                // Source tags
                if !heuristic.sourceTagSample.isEmpty {
                    Text(heuristic.sourceTagSample.prefix(5).map { "#\($0)" }.joined(separator: " "))
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalMercury)
                        .lineLimit(1)
                }

                // Footer: Confidence + Memory count
                HStack(spacing: 16) {
                    Label("\(heuristic.memoryCount)", systemImage: "square.stack.fill")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    Label("\(Int(heuristic.confidence * 100))%", systemImage: "checkmark.seal.fill")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(confidenceColor)

                    if heuristic.archived {
                        Label("Archived", systemImage: "archivebox.fill")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? AppColors.signalMercury.opacity(0.1) : AppColors.substrateSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? AppColors.signalMercury : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            isPressed = pressing
        }) {
            onLongPress()
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                onArchive()
            } label: {
                Label(
                    heuristic.archived ? "Unarchive" : "Archive",
                    systemImage: heuristic.archived ? "tray.full" : "archivebox"
                )
            }

            Divider()

            // Copy content
            Button {
                #if os(iOS)
                UIPasteboard.general.string = heuristic.content
                #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(heuristic.content, forType: .string)
                #endif
            } label: {
                Label("Copy Content", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Colors

    private var typeColor: Color {
        switch heuristic.type {
        case .frequency:
            return AppColors.signalMercury
        case .recency:
            return Color.orange
        case .curiosity:
            return Color.purple
        case .interest:
            return Color.pink
        }
    }

    private var confidenceColor: Color {
        if heuristic.confidence >= 0.8 {
            return .green
        } else if heuristic.confidence >= 0.6 {
            return .orange
        } else {
            return AppColors.textTertiary
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        HeuristicRow(
            heuristic: Heuristic(
                type: .frequency,
                dimension: .narrative,
                content: "Your recurring focus on 'sovereignty' and 'methodology' suggests a deep engagement with questions of agency and structured thinking.",
                sourceTagSample: ["sovereignty", "methodology", "agency", "thinking"],
                memoryCount: 15,
                confidence: 0.85
            ),
            isSelectionMode: false,
            isSelected: false,
            onTap: {},
            onLongPress: {},
            onArchive: {},
            onDelete: {}
        )

        HeuristicRow(
            heuristic: Heuristic(
                type: .recency,
                dimension: .embodiment,
                content: "This week you've been exploring 'workspaces' and 'navigation' heavily, suggesting active development work.",
                sourceTagSample: ["workspaces", "navigation", "ui", "swift"],
                memoryCount: 8,
                confidence: 0.72
            ),
            isSelectionMode: true,
            isSelected: true,
            onTap: {},
            onLongPress: {},
            onArchive: {},
            onDelete: {}
        )

        HeuristicRow(
            heuristic: Heuristic(
                type: .curiosity,
                dimension: .emotion,
                content: "Among recent tags, 'neuromorphic', 'emergence', and 'constraint' seem to pull at you with a sense of wonder.",
                sourceTagSample: ["neuromorphic", "emergence", "constraint"],
                memoryCount: 5,
                confidence: 0.65,
                archived: true
            ),
            isSelectionMode: false,
            isSelected: false,
            onTap: {},
            onLongPress: {},
            onArchive: {},
            onDelete: {}
        )
    }
    .padding()
    .background(AppColors.substratePrimary)
}
