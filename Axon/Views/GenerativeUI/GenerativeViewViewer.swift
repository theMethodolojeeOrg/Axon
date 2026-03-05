//
//  GenerativeViewViewer.swift
//  Axon
//
//  View mode for displaying a saved generative view
//  Normal app chrome, long press to enter edit mode
//

import SwiftUI

struct GenerativeViewViewer: View {
    let view: GenerativeViewDefinition
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showEditHint = true

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.substratePrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Rendered view
                        GenerativeUIRenderer.render(view.root)
                            .padding()
                            .frame(maxWidth: .infinity)

                        // Edit hint (dismissable)
                        if showEditHint && view.isEditable {
                            editHintBanner
                                .padding()
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        Spacer(minLength: 100)
                    }
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    // Long press to enter edit mode
                    onEdit()
                }
            }
            .navigationTitle(view.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit View", systemImage: "pencil")
                        }

                        if view.source == .bundle {
                            Button {
                                // Duplicate to edit
                                onEdit()
                            } label: {
                                Label("Duplicate & Edit", systemImage: "doc.on.doc")
                            }
                        }

                        Divider()

                        Button {
                            shareView()
                        } label: {
                            Label("Share JSON", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 600, minHeight: 400, idealHeight: 600)
        #endif
    }

    // MARK: - Edit Hint Banner

    private var editHintBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.tap")
                .font(.system(size: 20))
                .foregroundColor(AppColors.signalLichen)

            VStack(alignment: .leading, spacing: 2) {
                Text("Long press to edit")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text("Press and hold anywhere to enter edit mode")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Button {
                withAnimation {
                    showEditHint = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.substrateSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.signalLichen.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Actions

    private func shareView() {
        // Export JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(view.root),
              let json = String(data: data, encoding: .utf8) else { return }

        #if os(iOS)
        let activityVC = UIActivityViewController(
            activityItems: [json],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #else
        // macOS: Copy to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        #endif
    }
}
