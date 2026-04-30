//
//  BrowseMLXModelsView.swift
//  Axon
//
//  Browse and download MLX models from Hugging Face (mlx-community)
//

import SwiftUI

struct BrowseMLXModelsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var browserService = HuggingFaceMLXBrowserService.shared
    @StateObject private var mlxService = MLXModelService.shared

    @State private var searchText = ""
    @State private var selectedModel: HFModelInfo?
    @State private var showingModelDetail = false
    @State private var sortOption: SortOption = .downloads

    enum SortOption: String, CaseIterable {
        case downloads = "Downloads"
        case likes = "Likes"
        case recent = "Recent"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar

            // Sort options
            sortOptionsBar

            // Content
            if browserService.isSearching {
                loadingView
            } else if let error = browserService.searchError {
                errorView(error)
            } else if browserService.searchResults.isEmpty {
                emptyStateView
            } else {
                modelListView
            }
        }
        .background(AppSurfaces.color(.contentBackground))
        .navigationTitle("Browse MLX Models")
        .task {
            // Load popular models on appear
            if browserService.searchResults.isEmpty {
                await browserService.loadPopularModels()
            }
        }
        .sheet(isPresented: $showingModelDetail) {
            if let model = selectedModel {
                MLXModelDetailSheet(
                    modelInfo: model,
                    viewModel: viewModel,
                    browserService: browserService
                )
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textTertiary)

            TextField("Search Hugging Face models", text: $searchText)
                .font(AppTypography.bodyMedium())
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    Task {
                        await browserService.searchModels(query: searchText)
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Task {
                        await browserService.loadPopularModels()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(12)
        .padding()
    }

    // MARK: - Sort Options

    private var sortOptionsBar: some View {
        HStack(spacing: 12) {
            Text("Sort by:")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)

            ForEach(SortOption.allCases, id: \.self) { option in
                Button {
                    sortOption = option
                } label: {
                    Text(option.rawValue)
                        .font(AppTypography.labelSmall())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            sortOption == option
                                ? AppColors.signalMercury.opacity(0.2)
                                : AppSurfaces.color(.cardBackground)
                        )
                        .foregroundColor(
                            sortOption == option
                                ? AppColors.signalMercury
                                : AppColors.textSecondary
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("\(browserService.searchResults.count) models")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Model List

    private var modelListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sortedResults) { model in
                    MLXModelSearchRow(
                        model: model,
                        isDownloaded: browserService.isModelDownloaded(model.id),
                        isDownloading: browserService.isDownloading(model.id),
                        downloadProgress: browserService.progress(for: model.id)
                    ) {
                        selectedModel = model
                        showingModelDetail = true
                    }
                }
            }
            .padding()
        }
    }

    private var sortedResults: [HFModelInfo] {
        switch sortOption {
        case .downloads:
            return browserService.searchResults.sorted { ($0.downloads ?? 0) > ($1.downloads ?? 0) }
        case .likes:
            return browserService.searchResults.sorted { ($0.likes ?? 0) > ($1.likes ?? 0) }
        case .recent:
            return browserService.searchResults.sorted {
                ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast)
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Searching mlx-community models...")
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textSecondary)
            Spacer()
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(AppColors.accentError)
            Text("Search Failed")
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.textPrimary)
            Text(error)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try Again") {
                Task {
                    await browserService.searchModels(query: searchText)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.signalMercury)
            Spacer()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)
            Text("No Models Found")
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.textPrimary)
            Text("Try a different search term or browse popular models.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Browse Popular") {
                searchText = ""
                Task {
                    await browserService.loadPopularModels()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.signalMercury)
            Spacer()
        }
    }
}

// MARK: - Model Search Row

struct MLXModelSearchRow: View {
    let model: HFModelInfo
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Header row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Author
                        Text(model.author)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)

                        // Model name
                        Text(model.name)
                            .font(AppTypography.titleSmall())
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Status badge
                    if isDownloading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("\(Int(downloadProgress * 100))%")
                                .font(AppTypography.labelSmall())
                        }
                        .foregroundColor(AppColors.signalMercury)
                    } else if isDownloaded {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.accentSuccess)
                    }
                }

                // Meta row
                HStack(spacing: 16) {
                    // Last modified
                    if !model.lastModifiedString.isEmpty {
                        Label(model.lastModifiedString, systemImage: "clock")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    // Downloads
                    if !model.downloadsString.isEmpty {
                        Label(model.downloadsString, systemImage: "arrow.down.circle")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    // Likes
                    if let likes = model.likes, likes > 0 {
                        Label("\(likes)", systemImage: "heart")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Spacer()

                    // Vision badge
                    if model.isVisionModel {
                        Text("Vision")
                            .font(AppTypography.labelSmall())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(AppColors.signalLichen.opacity(0.2))
                            .foregroundColor(AppColors.signalLichen)
                            .cornerRadius(4)
                    }
                }

                // Download progress bar
                if isDownloading {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: AppColors.signalMercury))
                }
            }
            .padding()
            .background(AppSurfaces.color(.cardBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isDownloaded ? AppColors.accentSuccess.opacity(0.5) : AppSurfaces.color(.cardBorder),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model Detail Sheet

struct MLXModelDetailSheet: View {
    let modelInfo: HFModelInfo
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var browserService: HuggingFaceMLXBrowserService

    @Environment(\.dismiss) private var dismiss
    @State private var detailedInfo: HFModelDetailedInfo?
    @State private var isLoadingDetails = false
    @State private var loadError: String?
    @State private var isDownloading = false
    @State private var showDeleteConfirmation = false

    private var isDownloaded: Bool {
        browserService.isModelDownloaded(modelInfo.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header - always show immediately using modelInfo
                    headerSection

                    Divider()
                        .background(AppSurfaces.color(.cardBorder))

                    // Info section
                    if isLoadingDetails {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading model details...")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if let details = detailedInfo {
                        detailsSection(details)
                    } else if let error = loadError {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 32))
                                .foregroundColor(AppColors.accentError)
                            Text("Failed to load details")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)
                            Text(error)
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                Task { await loadDetails() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }

                    // Actions - always show
                    actionsSection
                }
                .padding()
            }
            .background(AppSurfaces.color(.contentBackground))
            #if os(macOS)
            // Prevent overly compact sheets on macOS.
            .frame(minWidth: 500, idealWidth: 600, minHeight: 550, idealHeight: 700)
            #endif
            .navigationTitle("Model Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadDetails()
            }
            .alert("Delete Model?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        try? await browserService.deleteModel(modelInfo.id)
                        // Remove from user models
                        await viewModel.removeUserMLXModel(repoId: modelInfo.id)
                    }
                }
            } message: {
                Text("This will permanently delete \(modelInfo.name) from your device. You can re-download it later.")
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .center, spacing: 12) {
            // Model icon
            Image(systemName: modelInfo.isVisionModel ? "eye.circle.fill" : "cpu.fill")
                .font(.system(size: 48))
                .foregroundColor(AppColors.signalMercury)

            // Author
            Text(modelInfo.author)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)

            // Name
            Text(modelInfo.name)
                .font(AppTypography.headlineMedium())
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            // Tags
            if modelInfo.isVisionModel {
                Text("Vision-Language Model")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.signalLichen)
            }

            // View on HF link
            Link(destination: URL(string: "https://huggingface.co/\(modelInfo.id)")!) {
                Label("View on Hugging Face", systemImage: "arrow.up.right.square")
                    .font(AppTypography.labelSmall())
            }
            .foregroundColor(AppColors.signalMercury)
        }
        .frame(maxWidth: .infinity)
    }

    private func detailsSection(_ details: HFModelDetailedInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Info")
                .font(AppTypography.titleSmall())
                .foregroundColor(AppColors.textPrimary)

            // Info grid
            VStack(spacing: 12) {
                if let params = details.parameterCount {
                    infoRow(label: "Size", value: "\(params) parameters")
                }

                if let quant = details.quantization {
                    infoRow(label: "Quantization", value: quant)
                }

                if let context = details.contextLength {
                    infoRow(label: "Context Length", value: "\(context / 1000)K tokens")
                }

                if let license = details.license {
                    infoRow(label: "License", value: license)
                }

                if let size = details.estimatedSize {
                    infoRow(label: "Est. Download", value: size)
                }

                if isDownloaded, let actualSize = browserService.getModelSize(modelInfo.id) {
                    infoRow(label: "On Disk", value: formatBytes(actualSize))
                }
            }
            .padding()
            .background(AppSurfaces.color(.cardBackground))
            .cornerRadius(12)

            // Description
            if let description = details.description {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(AppTypography.titleSmall())
                        .foregroundColor(AppColors.textPrimary)

                    Text(description)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(AppTypography.bodySmall(.medium))
                .foregroundColor(AppColors.textPrimary)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            if browserService.isDownloading(modelInfo.id) {
                // Download in progress
                VStack(spacing: 8) {
                    ProgressView(value: browserService.progress(for: modelInfo.id))
                        .progressViewStyle(LinearProgressViewStyle(tint: AppColors.signalMercury))

                    Text("Downloading... \(Int(browserService.progress(for: modelInfo.id) * 100))%")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding()
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(12)
            } else if isDownloaded {
                // Already downloaded
                HStack(spacing: 12) {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.accentError)

                    Button {
                        Task {
                            await viewModel.selectMLXModel(repoId: modelInfo.id)
                            dismiss()
                        }
                    } label: {
                        Label("Use Model", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.signalMercury)
                }
            } else {
                // Not downloaded
                Button {
                    Task {
                        await downloadModel()
                    }
                } label: {
                    Label("Download Model", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.signalMercury)
            }
        }
    }

    // MARK: - Actions

    private func loadDetails() async {
        isLoadingDetails = true
        loadError = nil

        do {
            detailedInfo = try await browserService.getModelDetails(repoId: modelInfo.id)
        } catch {
            loadError = error.localizedDescription
        }

        isLoadingDetails = false
    }

    private func downloadModel() async {
        do {
            try await browserService.downloadModel(repoId: modelInfo.id)

            // Add to user models
            let userModel = UserMLXModel(
                id: UUID(),
                repoId: modelInfo.id,
                displayName: modelInfo.name,
                downloadStatus: .downloaded,
                sizeBytes: browserService.getModelSize(modelInfo.id),
                contextWindow: detailedInfo?.contextLength ?? 8192,
                modalities: modelInfo.isVisionModel ? ["text", "vision"] : ["text"],
                addedAt: Date()
            )
            await viewModel.addUserMLXModel(userModel)
        } catch {
            // Error handling is done via browserService.searchError
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BrowseMLXModelsView(viewModel: SettingsViewModel.shared)
    }
}
