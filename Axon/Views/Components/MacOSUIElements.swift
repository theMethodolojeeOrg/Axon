//
//  MacOSUIElements.swift
//  Axon
//
//  Reusable macOS-specific UI components that provide native behavior
//  (e.g., Menu-based pickers that work reliably in sheets).
//

import SwiftUI

// MARK: - Styled Menu Picker

/// A pre-styled menu picker with icon, title, and standard Axon styling.
/// Works reliably on both macOS (using Menu) and iOS (using Picker).
///
/// Usage:
/// ```swift
/// StyledMenuPicker(
///     icon: "cpu.fill",
///     title: currentProvider?.displayName ?? "Select Provider",
///     selection: $selectedId
/// ) {
///     #if os(macOS)
///     Section("Built-in Providers") {
///         ForEach(providers) { provider in
///             MenuButtonItem(
///                 id: provider.id,
///                 label: provider.name,
///                 isSelected: selectedId == provider.id
///             ) {
///                 selectedId = provider.id
///             }
///         }
///     }
///     #else
///     Section("Built-in Providers") {
///         ForEach(providers) { provider in
///             Text(provider.name).tag(provider.id)
///         }
///     }
///     #endif
/// }
/// ```
struct StyledMenuPicker<Content: View>: View {
    let icon: String
    let title: String
    @Binding var selection: String
    @ViewBuilder let content: () -> Content

    /// Optional icon color override (defaults to signalMercury)
    var iconColor: Color = AppColors.signalMercury

    var body: some View {
        #if os(macOS)
        Menu {
            content()
        } label: {
            pickerLabel
        }
        .menuStyle(.borderlessButton)
        #else
        Picker(selection: $selection) {
            content()
        } label: {
            pickerLabel
        }
        .pickerStyle(.menu)
        #endif
    }

    private var pickerLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 32)

            Text(title)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            #if os(macOS)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppColors.textSecondary)
            #endif
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppSurfaces.color(.controlBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppSurfaces.color(.cardBorder), lineWidth: 1)
                )
        )
    }
}

// MARK: - Menu Button Item

/// A button for use inside Menu on macOS that shows a checkmark when selected.
/// Use this inside `StyledMenuPicker` content on macOS.
///
/// Example:
/// ```swift
/// #if os(macOS)
/// MenuButtonItem(
///     id: "anthropic",
///     label: "Anthropic",
///     isSelected: currentId == "anthropic"
/// ) {
///     currentId = "anthropic"
/// }
/// #else
/// Text("Anthropic").tag("anthropic")
/// #endif
/// ```
struct MenuButtonItem: View {
    let id: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSelected {
                SwiftUI.Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MacOSUIElements_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            StyledMenuPicker(
                icon: "cpu.fill",
                title: "Anthropic",
                selection: .constant("anthropic")
            ) {
                Text("Anthropic").tag("anthropic")
                Text("OpenAI").tag("openai")
            }

            StyledMenuPicker(
                icon: "brain.head.profile",
                title: "Claude 3.5 Sonnet",
                selection: .constant("sonnet")
            ) {
                Text("Claude 3.5 Sonnet").tag("sonnet")
                Text("Claude 3.5 Haiku").tag("haiku")
            }
        }
        .padding()
        .appSurface(.contentBackground)
    }
}
#endif
