//
//  WorkspacesView.swift
//  Axon
//
//  Main view for listing and managing workspaces.
//

import SwiftUI

struct WorkspacesView: View {
    @StateObject private var viewModel = WorkspaceViewModel.shared

    var body: some View {
        ZStack {
            AppColors.substratePrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Search bar
                WorkspaceSearchBar(text: $viewModel.searchText)
                    .padding()

                // Workspace list
                if viewModel.filteredWorkspaces.isEmpty {
                    WorkspacesEmptyState(
                        hasSearch: !viewModel.searchText.isEmpty,
                        onCreate: { viewModel.showCreateSheet = true }
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.filteredWorkspaces) { workspace in
                                WorkspaceRow(workspace: workspace)
                                    .onTapGesture {
                                        viewModel.selectWorkspace(workspace)
                                    }
                                    .contextMenu {
                                        Button {
                                            viewModel.startEditing(workspace)
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }

                                        Divider()

                                        Button(role: .destructive) {
                                            viewModel.deleteWorkspace(workspace)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }

            // FAB for creating new workspace
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { viewModel.showCreateSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(AppColors.signalMercury)
                            .clipShape(Circle())
                            .shadow(color: AppColors.shadow, radius: 8, x: 0, y: 4)
                    }
                    .padding()
                }
            }
        }
        // Success/Error toast overlays
        .overlay(alignment: .top) {
            if let message = viewModel.successMessage {
                WorkspaceSuccessToast(message: message)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        viewModel.successMessage = nil
                    }
            }

            if let error = viewModel.error {
                WorkspaceErrorToast(message: error)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        viewModel.error = nil
                    }
            }
        }
        .animation(AppAnimations.standardEasing, value: viewModel.successMessage != nil)
        .animation(AppAnimations.standardEasing, value: viewModel.error != nil)
        .sheet(isPresented: $viewModel.showCreateSheet) {
            Group {
            CreateWorkspaceSheet()
                .environmentObject(viewModel)

            }
            .appSheetMaterial()
}
        .sheet(isPresented: $viewModel.showEditSheet) {
            Group {
            if let workspace = viewModel.editingWorkspace {
                EditWorkspaceSheet(workspace: workspace)
                    .environmentObject(viewModel)
            }

            }
            .appSheetMaterial()
}
        .sheet(item: $viewModel.selectedWorkspace) {
            workspace in
            Group {
            WorkspaceDetailView(workspace: workspace)
                .environmentObject(viewModel)

            }
            .appSheetMaterial()
}
    }
}

// MARK: - Search Bar

struct WorkspaceSearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textSecondary)

            TextField("Search workspaces...", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .padding(12)
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
    }
}

// MARK: - Empty State

struct WorkspacesEmptyState: View {
    let hasSearch: Bool
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: hasSearch ? "magnifyingglass" : "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)

            Text(hasSearch ? "No Workspaces Found" : "No Workspaces Yet")
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.textSecondary)

            Text(hasSearch
                 ? "Try a different search term."
                 : "Create a workspace to organize your conversations and memories by project or topic.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if !hasSearch {
                Button(action: onCreate) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Create Workspace")
                    }
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppColors.signalMercury)
                    .cornerRadius(12)
                }
                .padding(.top, 8)
            }

            Spacer()
        }
    }
}

// MARK: - Toast Views

struct WorkspaceSuccessToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppColors.accentSuccess)

            Text(message)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)

            Spacer()
        }
        .padding()
        .appMaterialSurface(radius: 12)
        .shadow(color: AppColors.shadowStrong, radius: 8, x: 0, y: 4)
        .padding()
    }
}

struct WorkspaceErrorToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentError)

            Text(message)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)

            Spacer()
        }
        .padding()
        .appMaterialSurface(radius: 12)
        .shadow(color: AppColors.shadowStrong, radius: 8, x: 0, y: 4)
        .padding()
    }
}

// MARK: - Preview

#Preview {
    WorkspacesView()
}
