//
//  ContextDebugView.swift
//  Axon
//
//  Display context window breakdown for debugging token usage
//

import SwiftUI

// MARK: - Context Debug View (Expandable)

struct ContextDebugView: View {
    let debugInfo: ContextDebugInfo
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header - Always visible
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ant.fill")
                        .font(.system(size: 12))

                    Text("\(formatNumber(debugInfo.totalTokens)) / \(formatNumber(debugInfo.contextWindowLimit))")
                        .font(AppTypography.labelSmall())

                    // Usage bar (mini)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppColors.substrateTertiary)
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(usageColor)
                                .frame(width: geometry.size.width * debugInfo.usagePercentage, height: 4)
                        }
                    }
                    .frame(width: 40, height: 4)

                    Text("\(Int(debugInfo.usagePercentage * 100))%")
                        .font(AppTypography.labelSmall())

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(debugInfo.isOverLimit ? AppColors.accentError : (debugInfo.isNearLimit ? AppColors.accentWarning : AppColors.signalMercury))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    (debugInfo.isOverLimit ? AppColors.accentError : AppColors.signalMercury)
                        .opacity(0.1)
                )
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded breakdown
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    // Model info
                    HStack {
                        Text(debugInfo.modelName)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                        Spacer()
                        Text("Context: \(formatNumber(debugInfo.contextWindowLimit))")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding(.bottom, 4)

                    Divider()
                        .background(AppColors.divider)

                    // Token breakdown rows
                    ContextBreakdownRow(
                        icon: "doc.text",
                        label: "System Prompt",
                        tokens: debugInfo.systemPromptTokens
                    )

                    if debugInfo.memoriesCount > 0 {
                        ContextBreakdownRow(
                            icon: "brain.head.profile",
                            label: "Memories (\(debugInfo.memoriesCount))",
                            tokens: debugInfo.memoriesTokens
                        )
                    }

                    if debugInfo.factsCount > 0 {
                        ContextBreakdownRow(
                            icon: "lightbulb",
                            label: "Grounded Facts (\(debugInfo.factsCount))",
                            tokens: debugInfo.factsTokens
                        )
                    }

                    if debugInfo.summaryTokens > 0 {
                        ContextBreakdownRow(
                            icon: "clock.arrow.circlepath",
                            label: "Conversation Summary",
                            tokens: debugInfo.summaryTokens
                        )
                    }

                    if debugInfo.toolPromptTokens > 0 {
                        ContextBreakdownRow(
                            icon: "wrench.and.screwdriver",
                            label: "Tool Prompts",
                            tokens: debugInfo.toolPromptTokens
                        )
                    }

                    ContextBreakdownRow(
                        icon: "bubble.left.and.bubble.right",
                        label: "Messages",
                        tokens: debugInfo.messagesTokens
                    )

                    Divider()
                        .background(AppColors.divider)

                    // Total
                    HStack {
                        Image(systemName: "sum")
                            .font(.system(size: 12))
                            .foregroundColor(usageColor)
                            .frame(width: 20)

                        Text("Total")
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        Text(formatNumber(debugInfo.totalTokens))
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(usageColor)
                    }

                    // Warning if over limit
                    if debugInfo.isOverLimit {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                            Text("Exceeds context window by \(formatNumber(debugInfo.totalTokens - debugInfo.contextWindowLimit)) tokens")
                                .font(AppTypography.labelSmall())
                        }
                        .foregroundColor(AppColors.accentError)
                        .padding(.top, 4)
                    } else if debugInfo.isNearLimit {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 12))
                            Text("Approaching context limit (\(Int(debugInfo.usagePercentage * 100))% used)")
                                .font(AppTypography.labelSmall())
                        }
                        .foregroundColor(AppColors.accentWarning)
                        .padding(.top, 4)
                    }
                }
                .padding(12)
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var usageColor: Color {
        if debugInfo.isOverLimit {
            return AppColors.accentError
        } else if debugInfo.isNearLimit {
            return AppColors.accentWarning
        } else {
            return AppColors.signalMercury
        }
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        } else {
            return "\(number)"
        }
    }
}

// MARK: - Context Breakdown Row

private struct ContextBreakdownRow: View {
    let icon: String
    let label: String
    let tokens: Int

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(AppColors.textTertiary)
                .frame(width: 20)

            Text(label)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)

            Spacer()

            Text(formatNumber(tokens))
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textTertiary)
        }
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        } else {
            return "\(number)"
        }
    }
}

// MARK: - Compact Badge (for inline display)

struct ContextDebugBadge: View {
    let debugInfo: ContextDebugInfo

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "ant.fill")
                .font(.system(size: 10))
            Text("\(Int(debugInfo.usagePercentage * 100))%")
                .font(AppTypography.labelSmall())
        }
        .foregroundColor(badgeColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.1))
        .cornerRadius(12)
    }

    private var badgeColor: Color {
        if debugInfo.isOverLimit {
            return AppColors.accentError
        } else if debugInfo.isNearLimit {
            return AppColors.accentWarning
        } else {
            return AppColors.signalMercury
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Normal usage
        ContextDebugView(debugInfo: ContextDebugInfo(
            systemPromptTokens: 850,
            memoriesCount: 8,
            memoriesTokens: 3200,
            factsCount: 29,
            factsTokens: 4500,
            summaryTokens: 1200,
            toolPromptTokens: 2000,
            messagesTokens: 2500,
            contextWindowLimit: 200_000,
            modelName: "Claude Haiku 4.5"
        ))

        // Near limit
        ContextDebugView(debugInfo: ContextDebugInfo(
            systemPromptTokens: 850,
            memoriesCount: 50,
            memoriesTokens: 80_000,
            factsCount: 100,
            factsTokens: 60_000,
            summaryTokens: 15_000,
            toolPromptTokens: 5_000,
            messagesTokens: 10_000,
            contextWindowLimit: 200_000,
            modelName: "Claude Haiku 4.5"
        ))

        // Over limit
        ContextDebugView(debugInfo: ContextDebugInfo(
            systemPromptTokens: 850,
            memoriesCount: 50,
            memoriesTokens: 100_000,
            factsCount: 100,
            factsTokens: 80_000,
            summaryTokens: 15_000,
            toolPromptTokens: 5_000,
            messagesTokens: 10_000,
            contextWindowLimit: 200_000,
            modelName: "Claude Haiku 4.5"
        ))

        // Badge
        ContextDebugBadge(debugInfo: ContextDebugInfo(
            systemPromptTokens: 850,
            memoriesCount: 8,
            memoriesTokens: 3200,
            factsCount: 29,
            factsTokens: 4500,
            summaryTokens: 1200,
            toolPromptTokens: 2000,
            messagesTokens: 2500,
            contextWindowLimit: 200_000,
            modelName: "Claude Haiku 4.5"
        ))
    }
    .padding()
    .background(AppColors.substratePrimary)
}
