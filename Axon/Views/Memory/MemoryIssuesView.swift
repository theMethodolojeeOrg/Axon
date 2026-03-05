//
//  MemoryIssuesView.swift
//  Axon
//
//  View for displaying and resolving memory issues (duplicates and similar content)
//

import SwiftUI

// MARK: - Memory Issues Content View

struct MemoryIssuesContentView: View {
    @EnvironmentObject var viewModel: MemoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.memoryIssues.isEmpty {
                emptyStateView
            } else {
                // Header
                issuesHeader

                // Selection bar (when in selection mode)
                if viewModel.isIssueSelectionMode {
                    IssueSelectionBar()
                        .environmentObject(viewModel)
                }

                // Issues list
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.memoryIssues) { issue in
                            IssueCard(
                                issue: issue,
                                isSelectionMode: viewModel.isIssueSelectionMode,
                                isSelected: viewModel.selectedIssueIds.contains(issue.id),
                                selectedKeepId: viewModel.bulkKeepDecisions[issue.id]
                            )
                            .environmentObject(viewModel)
                        }
                    }
                    .padding()
                }
            }
        }
        .alert("Resolve Duplicate?", isPresented: $viewModel.showResolveConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.issueToResolve = nil
            }
            Button("Keep Selected", role: .destructive) {
                viewModel.resolveCurrentIssue()
            }
        } message: {
            if let resolution = viewModel.issueToResolve {
                let deleteCount = resolution.issue.memories.count - 1
                Text("This will delete \(deleteCount) duplicate memor\(deleteCount == 1 ? "y" : "ies") and keep the selected one.")
            }
        }
        .alert("Resolve \(viewModel.selectedIssueCount) Issues?", isPresented: $viewModel.showBulkResolveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Resolve All", role: .destructive) {
                viewModel.resolveSelectedIssues()
            }
        } message: {
            Text("This will keep the selected memory for each issue and delete all duplicates.")
        }
        .onAppear {
            viewModel.detectIssues()
        }
    }

    // MARK: - Header

    private var issuesHeader: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.signalCopper)

            Text("\(viewModel.issueCount) Issue\(viewModel.issueCount == 1 ? "" : "s") Found")
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            if !viewModel.isIssueSelectionMode {
                Button(action: { viewModel.enterIssueSelectionMode() }) {
                    Text("Select")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalMercury)
                }
                .padding(.trailing, 8)

                Button(action: { viewModel.detectIssues() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.signalMercury)
                }
            }
        }
        .padding()
        .background(AppColors.substrateSecondary)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(AppColors.accentSuccess)

            Text("No Issues Found")
                .font(AppTypography.headlineSmall())
                .foregroundColor(AppColors.textPrimary)

            Text("Your memories are in good shape. No duplicates or similar content detected.")
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: { viewModel.detectIssues() }) {
                Label("Scan Again", systemImage: "arrow.clockwise")
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.signalMercury)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Issue Selection Bar

private struct IssueSelectionBar: View {
    @EnvironmentObject var viewModel: MemoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Top row: Cancel, count, select all
            HStack(spacing: 16) {
                Button(action: { viewModel.exitIssueSelectionMode() }) {
                    Text("Cancel")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                Text("\(viewModel.selectedIssueCount) selected")
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button(action: {
                    if viewModel.allIssuesSelected {
                        viewModel.deselectAllIssues()
                    } else {
                        viewModel.selectAllIssues()
                    }
                }) {
                    Text(viewModel.allIssuesSelected ? "Deselect" : "Select All")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.signalMercury)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(AppColors.substrateSecondary)

            // Action buttons (when items selected)
            if viewModel.selectedIssueCount > 0 {
                HStack(spacing: 24) {
                    // Resolve button
                    Button(action: { viewModel.showBulkResolveConfirmation = true }) {
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 20))
                            Text("Resolve")
                                .font(AppTypography.labelSmall())
                        }
                        .foregroundColor(AppColors.signalMercury)
                    }

                    // Merge button (only for similar content)
                    Button(action: { viewModel.mergeSelectedIssues() }) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.merge")
                                .font(.system(size: 20))
                            Text("Merge")
                                .font(AppTypography.labelSmall())
                        }
                        .foregroundColor(AppColors.signalLichen)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(AppColors.substrateSecondary)
            }
        }
    }
}

// MARK: - Issue Card

private struct IssueCard: View {
    let issue: MemoryIssue
    let isSelectionMode: Bool
    let isSelected: Bool
    let selectedKeepId: String?
    @EnvironmentObject var viewModel: MemoryViewModel
    @State private var showMergeConfirmation = false

    private var issueColor: Color {
        switch issue.type {
        case .exactDuplicate:
            return AppColors.signalHematite
        case .similarContent:
            return AppColors.signalCopper
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Selection checkbox
            if isSelectionMode {
                Button(action: { viewModel.toggleIssueSelection(issue.id) }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 4)
            }

            // Card content
            VStack(alignment: .leading, spacing: 12) {
                // Issue type header
                HStack {
                    Image(systemName: issue.type.icon)
                        .foregroundColor(issueColor)

                    Text(issue.type.title)
                        .font(AppTypography.labelMedium())
                        .foregroundColor(issueColor)

                    if let similarity = issue.similarity, issue.type == .similarContent {
                        Text("(\(Int(similarity * 100))% match)")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Spacer()

                    // Merge button for similar content (only in non-selection mode)
                    if issue.type == .similarContent && !isSelectionMode {
                        Button(action: { showMergeConfirmation = true }) {
                            Label("Merge", systemImage: "arrow.triangle.merge")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.signalMercury)
                        }
                    }
                }

                // Content preview
                Text(issue.contentPreview)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)

                Divider()

                // Memory comparison
                VStack(spacing: 12) {
                    ForEach(Array(issue.memories.enumerated()), id: \.element.id) { index, memory in
                        MemoryComparisonRow(
                            memory: memory,
                            index: index,
                            totalCount: issue.memories.count,
                            isSelectionMode: isSelectionMode,
                            isSelectedToKeep: selectedKeepId == memory.id,
                            onKeep: {
                                if isSelectionMode {
                                    // In selection mode, just mark which one to keep
                                    viewModel.setKeepDecision(for: issue.id, keepMemoryId: memory.id)
                                    // Also select the issue if not already
                                    if !isSelected {
                                        viewModel.toggleIssueSelection(issue.id)
                                    }
                                } else {
                                    viewModel.prepareToResolve(issue: issue, keepingId: memory.id)
                                }
                            }
                        )

                        if index < issue.memories.count - 1 {
                            HStack {
                                Spacer()
                                Text("vs")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? AppColors.signalMercury.opacity(0.1) : AppColors.substrateSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? AppColors.signalMercury : issueColor.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                viewModel.toggleIssueSelection(issue.id)
            }
        }
        .alert("Merge Memories?", isPresented: $showMergeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Merge") {
                viewModel.mergeMemories(issue)
            }
        } message: {
            Text("This will combine the content of \(issue.memories.count) memories into one and delete the others.")
        }
    }
}

// MARK: - Memory Comparison Row

private struct MemoryComparisonRow: View {
    let memory: Memory
    let index: Int
    let totalCount: Int
    let isSelectionMode: Bool
    let isSelectedToKeep: Bool
    let onKeep: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Memory info
            VStack(alignment: .leading, spacing: 4) {
                // Date
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text(memory.createdAt, style: .date)
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(AppColors.textTertiary)

                // Access count
                HStack(spacing: 4) {
                    Image(systemName: "eye")
                        .font(.system(size: 10))
                    Text("\(memory.accessCount) accesses")
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(AppColors.textTertiary)

                // Confidence
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 10))
                    Text("\(Int(memory.confidence * 100))% confidence")
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(AppColors.textTertiary)

                // Tags preview
                if !memory.tags.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.system(size: 10))
                        Text(memory.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                            .font(AppTypography.labelSmall())
                            .lineLimit(1)
                    }
                    .foregroundColor(AppColors.textTertiary)
                }
            }

            Spacer()

            // Keep button / Selected indicator
            Button(action: onKeep) {
                HStack(spacing: 4) {
                    if isSelectionMode && isSelectedToKeep {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(isSelectionMode ? (isSelectedToKeep ? "Keeping" : "Keep") : "Keep This")
                        .font(AppTypography.labelMedium())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelectedToKeep ? AppColors.accentSuccess : AppColors.signalMercury)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelectedToKeep ? AppColors.accentSuccess.opacity(0.1) : AppColors.substrateTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelectedToKeep ? AppColors.accentSuccess : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    MemoryIssuesContentView()
        .environmentObject(MemoryViewModel.shared)
}
