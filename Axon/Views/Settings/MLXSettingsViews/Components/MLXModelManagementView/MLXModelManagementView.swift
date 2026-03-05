//
//  MLXModelManagementView.swift
//  Axon
//
//  Comprehensive MLX model management with download, delete, and memory controls.
//  Includes browsing and downloading models from Hugging Face.
//

import SwiftUI

struct MLXModelManagementView: View {
    @ObservedObject var viewModel: SettingsViewModel = SettingsViewModel.shared
    @ObservedObject var mlxService = MLXModelService.shared
    @StateObject private var browserService = HuggingFaceMLXBrowserService.shared

    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: String?  // repoId
    @State private var modelToDeleteName: String = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Storage Summary Card
            storageSummaryCard

            // Browse More Models button
            browseModelsButton

            // Bundled Model (always first)
            bundledModelSection

            // Downloaded User Models
            if !viewModel.settings.userMLXModels.isEmpty {
                userModelsSection
            }

            // Built-in downloadable models (excluding bundled)
            builtInModelsSection
        }
        .alert("Delete Model?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let repoId = modelToDelete {
                    deleteModel(repoId: repoId)
                }
            }
        } message: {
            Text("This will permanently delete \(modelToDeleteName) from your device. You can re-download it later if needed.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Storage Summary

    private var storageSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "internaldrive")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.signalMercury)

                Text("Model Storage")
                    .font(AppTypography.titleSmall())
                    .foregroundColor(AppColors.textPrimary)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Downloaded:")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text("\(downloadedCount) models")
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textPrimary)
                }

                HStack {
                    Text("Space Used:")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text(formatBytes(totalStorageUsed))
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textPrimary)
                }

                if let memoryModel = mlxService.modelInMemory {
                    let displayName = modelDisplayName(for: memoryModel)
                    HStack {
                        Text("In Memory:")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "brain")
                                .font(.system(size: 12))
                            Text(displayName)
                        }
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.signalLichen)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.substrateSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Browse Button

    private var browseModelsButton: some View {
        NavigationLink {
            BrowseMLXModelsView(viewModel: viewModel)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.signalMercury)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse More Models")
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text("Search and download from Hugging Face")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColors.signalMercury.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.signalMercury.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bundled Model Section

    private var bundledModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bundled Model")
                .font(AppTypography.titleSmall())
                .foregroundColor(AppColors.textPrimary)

            MLXModelCard(
                repoId: LocalMLXModel.defaultModel.rawValue,
                displayName: LocalMLXModel.defaultModel.displayName,
                description: LocalMLXModel.defaultModel.description,
                isBundled: true,
                isVision: LocalMLXModel.defaultModel.modalities.contains("vision"),
                mlxService: mlxService,
                browserService: browserService,
                isSelected: viewModel.selectedMLXModelId() == LocalMLXModel.defaultModel.rawValue,
                onSelect: {
                    Task {
                        await viewModel.selectMLXModel(repoId: LocalMLXModel.defaultModel.rawValue)
                    }
                },
                onDelete: nil,  // Can't delete bundled
                onError: { error in
                    errorMessage = error
                    showError = true
                }
            )
        }
    }

    // MARK: - User Models Section

    private var userModelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Downloaded Models")
                .font(AppTypography.titleSmall())
                .foregroundColor(AppColors.textPrimary)

            ForEach(viewModel.settings.userMLXModels) { userModel in
                MLXModelCard(
                    repoId: userModel.repoId,
                    displayName: userModel.displayName,
                    description: "User-added model from Hugging Face",
                    isBundled: false,
                    isVision: userModel.modalities.contains("vision"),
                    mlxService: mlxService,
                    browserService: browserService,
                    isSelected: viewModel.selectedMLXModelId() == userModel.repoId,
                    onSelect: {
                        Task {
                            await viewModel.selectMLXModel(repoId: userModel.repoId)
                        }
                    },
                    onDelete: {
                        modelToDelete = userModel.repoId
                        modelToDeleteName = userModel.displayName
                        showDeleteConfirmation = true
                    },
                    onError: { error in
                        errorMessage = error
                        showError = true
                    }
                )
            }
        }
    }

    // MARK: - Built-in Models Section

    private var builtInModelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Other Available Models")
                .font(AppTypography.titleSmall())
                .foregroundColor(AppColors.textPrimary)

            ForEach(LocalMLXModel.allCases.filter { !$0.isBundled }, id: \.rawValue) { model in
                MLXModelCard(
                    repoId: model.rawValue,
                    displayName: model.displayName,
                    description: model.description,
                    isBundled: false,
                    isVision: model.modalities.contains("vision"),
                    mlxService: mlxService,
                    browserService: browserService,
                    isSelected: viewModel.selectedMLXModelId() == model.rawValue,
                    onSelect: {
                        Task {
                            await viewModel.selectMLXModel(repoId: model.rawValue)
                        }
                    },
                    onDelete: {
                        modelToDelete = model.rawValue
                        modelToDeleteName = model.displayName
                        showDeleteConfirmation = true
                    },
                    onError: { error in
                        errorMessage = error
                        showError = true
                    }
                )
            }
        }
    }

    // MARK: - Helpers

    private var downloadedCount: Int {
        // Count bundled (always available) + downloaded built-in + user models
        var count = 1  // Bundled model

        // Built-in models that are downloaded
        for model in LocalMLXModel.allCases where !model.isBundled {
            if mlxService.downloadedModels.contains(model.rawValue) ||
               browserService.isModelDownloaded(model.rawValue) {
                count += 1
            }
        }

        // User models that are downloaded
        count += viewModel.settings.userMLXModels.filter { $0.downloadStatus == .downloaded }.count

        return count
    }

    private var totalStorageUsed: Int64 {
        var total: Int64 = 0

        // Built-in models
        for model in LocalMLXModel.allCases {
            if let size = mlxService.getModelSize(modelId: model.rawValue) {
                total += size
            } else if let size = browserService.getModelSize(model.rawValue) {
                total += size
            }
        }

        // User models from browser service
        total += browserService.getTotalDownloadedSize()

        return total
    }

    private func modelDisplayName(for repoId: String) -> String {
        // Check built-in models
        if let model = LocalMLXModel.allCases.first(where: { $0.rawValue == repoId }) {
            return model.displayName
        }
        // Check user models
        if let userModel = viewModel.settings.userMLXModels.first(where: { $0.repoId == repoId }) {
            return userModel.displayName
        }
        // Fallback to repo name
        return repoId.components(separatedBy: "/").last ?? repoId
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "Zero KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func deleteModel(repoId: String) {
        Task {
            do {
                // Delete from MLX service cache
                try await mlxService.deleteModel(modelId: repoId)

                // Delete from browser service storage
                try await browserService.deleteModel(repoId)

                // Remove from user models if it's a user model
                await viewModel.removeUserMLXModel(repoId: repoId)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - MLX Model Card

struct MLXModelCard: View {
    let repoId: String
    let displayName: String
    let description: String
    let isBundled: Bool
    let isVision: Bool
    @ObservedObject var mlxService: MLXModelService
    @ObservedObject var browserService: HuggingFaceMLXBrowserService
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?
    let onError: (String) -> Void

    private var isDownloaded: Bool {
        isBundled ||
        mlxService.downloadedModels.contains(repoId) ||
        browserService.isModelDownloaded(repoId)
    }

    private var isDownloading: Bool {
        mlxService.downloadingModel == repoId ||
        browserService.isDownloading(repoId)
    }

    private var isInMemory: Bool {
        mlxService.modelInMemory == repoId
    }

    private var downloadProgress: Double {
        if mlxService.downloadingModel == repoId {
            return mlxService.downloadProgress
        }
        return browserService.progress(for: repoId)
    }

    private var modelSize: String? {
        if let size = mlxService.getModelSize(modelId: repoId) {
            return formatBytes(size)
        }
        if let size = browserService.getModelSize(repoId) {
            return formatBytes(size)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: isVision ? "eye.circle.fill" : "cpu")
                    .font(.system(size: 24))
                    .foregroundColor(statusColor)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(AppTypography.titleSmall())
                            .foregroundColor(AppColors.textPrimary)

                        if isBundled {
                            Text("Bundled")
                                .font(AppTypography.labelSmall())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.signalMercury.opacity(0.2))
                                .foregroundColor(AppColors.signalMercury)
                                .cornerRadius(4)
                        }

                        if isSelected {
                            Text("Active")
                                .font(AppTypography.labelSmall())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.accentSuccess.opacity(0.2))
                                .foregroundColor(AppColors.accentSuccess)
                                .cornerRadius(4)
                        }
                    }

                    Text(description)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                // Status indicator
                statusIndicator
            }

            // Status text
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.system(size: 12))
                    .foregroundColor(statusColor)

                Text(statusText)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(statusColor)

                if let size = modelSize {
                    Text("•")
                        .foregroundColor(AppColors.textTertiary)
                    Text(size)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
            }

            // Download progress bar
            if isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: AppColors.signalMercury))

                    Text(mlxService.loadingStatus.isEmpty ? "Downloading..." : mlxService.loadingStatus)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                if isDownloaded && !isDownloading {
                    // Select button (if not already selected)
                    if !isSelected {
                        Button(action: onSelect) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 14))
                                Text("Use")
                                    .font(AppTypography.labelSmall())
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppColors.signalMercury)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Memory toggle
                    Button(action: toggleMemory) {
                        HStack(spacing: 6) {
                            Image(systemName: isInMemory ? "brain.filled.head.profile" : "brain.head.profile")
                                .font(.system(size: 14))
                            Text(isInMemory ? "Unload" : "Load")
                                .font(AppTypography.labelSmall())
                        }
                        .foregroundColor(isInMemory ? AppColors.signalLichen : AppColors.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isInMemory ? AppColors.signalLichen : AppColors.glassBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    // Delete button (not for bundled models)
                    if !isBundled, let onDelete = onDelete {
                        Button(action: onDelete) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14))
                                Text("Delete")
                                    .font(AppTypography.labelSmall())
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.red.opacity(0.5), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                } else if !isDownloaded && !isDownloading && !isBundled {
                    // Download button
                    Button(action: downloadModel) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 14))
                            Text("Download")
                                .font(AppTypography.labelSmall())
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppColors.signalMercury)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? AppColors.signalMercury.opacity(0.1) : (isInMemory ? AppColors.signalLichen.opacity(0.1) : AppColors.substrateSecondary))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? AppColors.signalMercury : (isInMemory ? AppColors.signalLichen : AppColors.glassBorder), lineWidth: 1)
                )
        )
    }

    // MARK: - Status Helpers

    private var statusColor: Color {
        if isDownloading {
            return AppColors.signalMercury
        } else if isInMemory {
            return AppColors.signalLichen
        } else if isDownloaded {
            return AppColors.accentSuccess
        } else {
            return AppColors.textTertiary
        }
    }

    private var statusIcon: String {
        if isDownloading {
            return "arrow.down.circle"
        } else if isInMemory {
            return "brain.filled.head.profile"
        } else if isDownloaded {
            return "checkmark.circle.fill"
        } else {
            return "circle"
        }
    }

    private var statusText: String {
        if isDownloading {
            return "Downloading..."
        } else if isInMemory {
            return "In Memory"
        } else if isDownloaded || isBundled {
            return isBundled ? "Ready" : "Downloaded"
        } else {
            return "Not Downloaded"
        }
    }

    private var statusIndicator: some View {
        Group {
            if isDownloading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.signalMercury))
                    .scaleEffect(0.8)
            } else if isInMemory {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.signalLichen)
            } else if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.accentSuccess)
            }
        }
    }

    // MARK: - Actions

    private func downloadModel() {
        Task {
            do {
                try await mlxService.loadModel(modelId: repoId)
            } catch {
                onError(error.localizedDescription)
            }
        }
    }

    private func toggleMemory() {
        if isInMemory {
            mlxService.unloadModel()
        } else {
            Task {
                do {
                    try await mlxService.loadModel(modelId: repoId)
                } catch {
                    onError(error.localizedDescription)
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScrollView {
            MLXModelManagementView()
                .padding()
        }
        .background(AppColors.substratePrimary)
    }
}
