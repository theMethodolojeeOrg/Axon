//
//  MLXModelManagementView.swift
//  Axon
//
//  Comprehensive MLX model management with download, delete, and memory controls
//

import SwiftUI

struct MLXModelManagementView: View {
    @ObservedObject var mlxService = MLXModelService.shared
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: LocalMLXModel?
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Storage Summary Card
            storageSummaryCard
            
            // Model Cards
            ForEach(LocalMLXModel.allCases, id: \.rawValue) { model in
                MLXModelCard(
                    model: model,
                    mlxService: mlxService,
                    onDelete: {
                        modelToDelete = model
                        showDeleteConfirmation = true
                    },
                    onError: { error in
                        errorMessage = error
                        showError = true
                    }
                )
            }
        }
        .alert("Delete Model?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    Task {
                        do {
                            try await mlxService.deleteModel(modelId: model.rawValue)
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
            }
        } message: {
            if let model = modelToDelete {
                Text("This will permanently delete \(model.displayName) from your device. You can re-download it later if needed.")
            }
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
                    Text("\(mlxService.downloadedModels.count) of \(LocalMLXModel.allCases.count) models")
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textPrimary)
                }
                
                HStack {
                    Text("Space Used:")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text(formatBytes(mlxService.getTotalModelsSize()))
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textPrimary)
                }
                
                if let memoryModel = mlxService.modelInMemory,
                   let model = LocalMLXModel.allCases.first(where: { $0.rawValue == memoryModel }) {
                    HStack {
                        Text("In Memory:")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "brain")
                                .font(.system(size: 12))
                            Text(model.displayName)
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
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - MLX Model Card

struct MLXModelCard: View {
    let model: LocalMLXModel
    @ObservedObject var mlxService: MLXModelService
    let onDelete: () -> Void
    let onError: (String) -> Void
    
    private var isDownloaded: Bool {
        mlxService.downloadedModels.contains(model.rawValue)
    }
    
    private var isDownloading: Bool {
        mlxService.downloadingModel == model.rawValue
    }
    
    private var isInMemory: Bool {
        mlxService.modelInMemory == model.rawValue
    }
    
    private var modelSize: String? {
        guard let size = mlxService.getModelSize(modelId: model.rawValue) else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 24))
                    .foregroundColor(statusColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(AppTypography.titleSmall())
                        .foregroundColor(AppColors.textPrimary)
                    
                    Text(model.description)
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
                    ProgressView(value: mlxService.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: AppColors.signalMercury))
                    
                    Text(mlxService.loadingStatus)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                if isDownloaded && !isDownloading {
                    // Delete button
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
                    
                } else if !isDownloaded && !isDownloading {
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
                .fill(isInMemory ? AppColors.signalLichen.opacity(0.1) : AppColors.substrateSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isInMemory ? AppColors.signalLichen : AppColors.glassBorder, lineWidth: 1)
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
        } else if isDownloaded {
            return "Downloaded"
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
                try await mlxService.loadModel(modelId: model.rawValue)
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
                    try await mlxService.loadModel(modelId: model.rawValue)
                } catch {
                    onError(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MLXModelManagementView()
            .padding()
    }
    .background(AppColors.substratePrimary)
}
