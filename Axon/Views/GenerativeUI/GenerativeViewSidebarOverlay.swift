//
//  GenerativeViewSidebarOverlay.swift
//  Axon
//
//  Swipe-down overlay for quick navigation between generative views
//

import SwiftUI
import Combine

struct GenerativeViewSidebarOverlay: View {
    let onSelectView: (GenerativeViewDefinition) -> Void
    let onClose: () -> Void

    @StateObject private var storageService = GenerativeViewStorageService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Handle indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(AppColors.textTertiary)
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Header
            HStack {
                Text("Generative Views")
                    .font(AppTypography.titleSmall())
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()
                .background(AppColors.divider)

            // Views list
            if storageService.allViews.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(storageService.allViews) { view in
                            viewRow(for: view)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppColors.substrateSecondary)
                .shadow(color: AppColors.shadowStrong, radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - View Row

    private func viewRow(for view: GenerativeViewDefinition) -> some View {
        Button {
            onSelectView(view)
        } label: {
            HStack(spacing: 12) {
                // Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppColors.substrateTertiary)

                    if let base64 = view.thumbnailBase64,
                       let data = Data(base64Encoded: base64),
                       let image = PlatformImageCodec.image(from: data) {
                        #if canImport(UIKit)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        #elseif canImport(AppKit)
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        #endif
                    } else {
                        Image(systemName: "rectangle.3.group")
                            .font(.system(size: 18))
                            .foregroundColor(AppColors.signalLichen)
                    }
                }
                .frame(width: 48, height: 48)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(view.name)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if view.source == .bundle {
                            Label("Template", systemImage: "doc.text")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.signalMercury)
                        } else {
                            Text("\(view.nodeCount) nodes")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColors.substratePrimary)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "rectangle.3.group")
                .font(.system(size: 32))
                .foregroundColor(AppColors.textTertiary)

            Text("No Views Yet")
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textSecondary)

            Text("Create your first generative view to get started")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }
}
