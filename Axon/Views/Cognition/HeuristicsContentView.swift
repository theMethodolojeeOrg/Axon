//
//  HeuristicsContentView.swift
//  Axon
//
//  Content view for the Heuristics tab showing synthesized insights
//  with filter chips for type and dimension.
//

import SwiftUI

struct HeuristicsContentView: View {
    @EnvironmentObject var viewModel: HeuristicsViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Type filter chips
            heuristicTypeFilters

            // Dimension sub-filter chips (when type selected)
            if viewModel.selectedType != nil {
                dimensionFilters
            }

            Divider()
                .background(AppColors.divider)

            // Heuristics list or empty state
            if viewModel.filteredHeuristics.isEmpty {
                emptyState
            } else {
                heuristicsList
            }
        }
        .overlay(alignment: .bottomTrailing) {
            synthesizeButton
        }
        // Selection bar at bottom
        .overlay(alignment: .bottom) {
            if viewModel.isSelectionMode {
                selectionBar
            }
        }
        // Toast messages
        .overlay(alignment: .top) {
            if let successMessage = viewModel.successMessage {
                HeuristicsSuccessToast(message: successMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        viewModel.successMessage = nil
                    }
            }

            if let errorMessage = viewModel.error {
                HeuristicsErrorToast(message: errorMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        viewModel.error = nil
                    }
            }
        }
        .animation(AppAnimations.standardEasing, value: viewModel.successMessage != nil)
        .animation(AppAnimations.standardEasing, value: viewModel.error != nil)
    }

    // MARK: - Type Filters

    private var heuristicTypeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All filter
                HeuristicFilterChip(
                    title: "All",
                    isSelected: viewModel.selectedType == nil
                ) {
                    viewModel.selectedType = nil
                    viewModel.selectedDimension = nil
                }

                // Type filters
                ForEach(HeuristicType.allCases) { type in
                    HeuristicFilterChip(
                        title: type.displayName,
                        icon: type.icon,
                        isSelected: viewModel.selectedType == type
                    ) {
                        if viewModel.selectedType == type {
                            viewModel.selectedType = nil
                            viewModel.selectedDimension = nil
                        } else {
                            viewModel.selectedType = type
                        }
                    }
                }

                // Archive toggle
                HeuristicFilterChip(
                    title: viewModel.showArchived ? "Archived" : "Active",
                    icon: viewModel.showArchived ? "archivebox.fill" : "tray.full",
                    isSelected: true
                ) {
                    viewModel.showArchived.toggle()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .appSurface(.overlayBackground)
    }

    // MARK: - Dimension Filters

    private var dimensionFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All dimensions
                HeuristicFilterChip(
                    title: "All",
                    isSelected: viewModel.selectedDimension == nil
                ) {
                    viewModel.selectedDimension = nil
                }

                ForEach(HeuristicDimension.allCases) { dim in
                    HeuristicFilterChip(
                        title: dim.displayName,
                        icon: dim.icon,
                        isSelected: viewModel.selectedDimension == dim
                    ) {
                        viewModel.selectedDimension =
                            viewModel.selectedDimension == dim ? nil : dim
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .appSurface(.overlayBackground)
    }

    // MARK: - Heuristics List

    private var heuristicsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredHeuristics) { heuristic in
                    HeuristicRow(
                        heuristic: heuristic,
                        isSelectionMode: viewModel.isSelectionMode,
                        isSelected: viewModel.selectedIds.contains(heuristic.id),
                        onTap: {
                            if viewModel.isSelectionMode {
                                viewModel.toggleSelection(heuristic.id)
                            } else {
                                viewModel.selectedHeuristic = heuristic
                            }
                        },
                        onLongPress: {
                            if !viewModel.isSelectionMode {
                                viewModel.enterSelectionMode(with: heuristic.id)
                            }
                        },
                        onArchive: {
                            viewModel.archive(heuristic)
                        },
                        onDelete: {
                            viewModel.delete(heuristic)
                        }
                    )
                }
            }
            .padding()
            .padding(.bottom, viewModel.isSelectionMode ? 80 : 80) // Space for FAB/selection bar
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)

            Text(viewModel.emptyStateTitle)
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.textPrimary)

            Text(viewModel.emptyStateMessage)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Synthesize FAB

    private var synthesizeButton: some View {
        Button {
            Task {
                await viewModel.synthesizeAll()
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isSynthesizing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "sparkles")
                }
                Text("Synthesize")
                    .font(AppTypography.bodyMedium(.medium))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(AppColors.signalMercury)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .disabled(viewModel.isSynthesizing)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .opacity(viewModel.isSelectionMode ? 0 : 1)
    }

    // MARK: - Selection Bar

    private var selectionBar: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.selectAll()
            } label: {
                Text("Select All")
                    .font(AppTypography.labelSmall())
            }

            Spacer()

            Text("\(viewModel.selectedCount) selected")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)

            Spacer()

            Button {
                viewModel.showArchiveConfirmation = true
            } label: {
                Image(systemName: viewModel.showArchived ? "tray.full" : "archivebox")
            }

            Button(role: .destructive) {
                viewModel.showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .foregroundColor(AppColors.accentError)

            Button {
                viewModel.exitSelectionMode()
            } label: {
                Text("Done")
                    .font(AppTypography.labelMedium())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .appSurface(.overlayBackground)
        .overlay(
            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 1),
            alignment: .top
        )
        .alert("Delete Heuristics", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                viewModel.deleteSelected()
            }
        } message: {
            Text("Are you sure you want to delete \(viewModel.selectedCount) heuristic(s)? This cannot be undone.")
        }
        .alert(viewModel.showArchived ? "Unarchive Heuristics" : "Archive Heuristics",
               isPresented: $viewModel.showArchiveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(viewModel.showArchived ? "Unarchive" : "Archive") {
                viewModel.archiveSelected()
            }
        } message: {
            let action = viewModel.showArchived ? "unarchive" : "archive"
            Text("Are you sure you want to \(action) \(viewModel.selectedCount) heuristic(s)?")
        }
    }
}

// MARK: - Filter Chip

struct HeuristicFilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                Text(title)
                    .font(AppTypography.labelSmall())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? AppColors.signalMercury : AppSurfaces.color(.controlBackground))
            )
            .foregroundColor(isSelected ? .white : AppColors.textSecondary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Toast Views

struct HeuristicsSuccessToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(message)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .appMaterialSurface(radius: 12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        .padding(.top, 8)
    }
}

struct HeuristicsErrorToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(AppColors.accentError)
            Text(message)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .appMaterialSurface(radius: 12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        .padding(.top, 8)
    }
}

// MARK: - Preview

#Preview {
    HeuristicsContentView()
        .environmentObject(HeuristicsViewModel.shared)
}
