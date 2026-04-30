//
//  ComponentPickerSheet.swift
//  Axon
//
//  Bottom sheet for selecting components to add to a generative view
//

import SwiftUI

struct ComponentPickerSheet: View {
    let onSelect: (GenerativeUIComponentType) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    // Component categories
    private let layoutComponents: [GenerativeUIComponentType] = [.vstack, .hstack, .zstack]
    private let contentComponents: [GenerativeUIComponentType] = [.text, .button, .image]
    private let utilityComponents: [GenerativeUIComponentType] = [.spacer, .divider]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Layout section
                    componentSection(
                        title: "Layout",
                        subtitle: "Organize content with stacks",
                        components: layoutComponents
                    )

                    // Content section
                    componentSection(
                        title: "Content",
                        subtitle: "Display information",
                        components: contentComponents
                    )

                    // Utility section
                    componentSection(
                        title: "Utility",
                        subtitle: "Spacing and dividers",
                        components: utilityComponents
                    )

                    Spacer()
                        .frame(height: 40)
                }
                .padding()
            }
            .background(Color.clear)
            .navigationTitle("Add Component")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 500)
        #endif
    }

    // MARK: - Section

    private func componentSection(title: String, subtitle: String, components: [GenerativeUIComponentType]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.titleSmall())
                    .foregroundColor(AppColors.textPrimary)

                Text(subtitle)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(components, id: \.rawValue) { component in
                    componentCard(for: component)
                }
            }
        }
    }

    // MARK: - Component Card

    private func componentCard(for type: GenerativeUIComponentType) -> some View {
        Button {
            onSelect(type)
        } label: {
            VStack(spacing: 12) {
                Image(systemName: iconForType(type))
                    .font(.system(size: 28))
                    .foregroundColor(colorForType(type))
                    .frame(width: 48, height: 48)
                    .background(colorForType(type).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 4) {
                    Text(type.rawValue)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(descriptionForType(type))
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppColors.substrateSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppColors.glassBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func iconForType(_ type: GenerativeUIComponentType) -> String {
        switch type {
        case .vstack: return "square.split.1x2"
        case .hstack: return "square.split.2x1"
        case .zstack: return "square.stack"
        case .text: return "textformat"
        case .button: return "button.horizontal"
        case .image: return "photo"
        case .spacer: return "arrow.up.and.down"
        case .divider: return "minus"
        }
    }

    private func colorForType(_ type: GenerativeUIComponentType) -> Color {
        switch type {
        case .vstack, .hstack, .zstack: return AppColors.signalMercury
        case .text, .button, .image: return AppColors.signalLichen
        case .spacer, .divider: return AppColors.signalCopper
        }
    }

    private func descriptionForType(_ type: GenerativeUIComponentType) -> String {
        switch type {
        case .vstack: return "Vertical stack"
        case .hstack: return "Horizontal stack"
        case .zstack: return "Layered stack"
        case .text: return "Display text"
        case .button: return "Tappable button"
        case .image: return "SF Symbol or image"
        case .spacer: return "Flexible space"
        case .divider: return "Separator line"
        }
    }
}

// MARK: - Preview

#Preview {
    ComponentPickerSheet(
        onSelect: { type in
            print("Selected: \(type.rawValue)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}
