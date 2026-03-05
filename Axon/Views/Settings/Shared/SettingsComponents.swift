//
//  SettingsComponents.swift
//  Axon
//
//  Shared components to keep Settings screens visually consistent.
//

import SwiftUI

/// General-style section used by Settings screens.
///
/// This intentionally matches the look/spacing used in `GeneralSettingsView`.
struct UnifiedSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTypography.headlineSmall())
                .foregroundColor(AppColors.textPrimary)

            content
        }
    }
}

/// A reusable “banner” card for short informational messages at the top of a settings screen.
struct SettingsInfoBanner: View {
    let icon: String
    let text: String
    var tint: Color = AppColors.signalMercury

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(tint)

            Text(text)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding()
        .background(tint.opacity(0.1))
        .cornerRadius(8)
    }
}

/// A consistent container card for setting blocks/rows.
struct SettingsCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.substrateSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
        )
    }
}

/// A container for settings subviews pushed via NavigationLink.
/// Wraps content in a ScrollView with the correct background color.
struct SettingsSubviewContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content
                .padding()
        }
        .background(AppColors.substratePrimary)
    }
}

/// A navigation row for settings category screens.
/// Used in category wrapper views (Providers, Automation, Privacy, Connectivity) to link to subviews.
struct SettingsCategoryRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.substrateSecondary)
        )
    }
}

// MARK: - Settings Slider Row

/// A reusable slider row with title, optional description, value display, and optional min/max labels.
/// Use for settings like thresholds, speeds, percentages, etc.
struct SettingsSliderRow: View {
    let title: String
    var description: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var valueFormatter: ((Double) -> String)? = nil
    var minLabel: String? = nil
    var maxLabel: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title and value
            HStack {
                Text(title)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Text(valueFormatter?(value) ?? String(format: "%.0f%%", value * 100))
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.signalMercury)
            }

            // Slider
            if let step = step {
                Slider(value: $value, in: range, step: step)
                    .tint(AppColors.signalMercury)
            } else {
                Slider(value: $value, in: range)
                    .tint(AppColors.signalMercury)
            }

            // Optional min/max labels
            if minLabel != nil || maxLabel != nil {
                HStack {
                    if let minLabel = minLabel {
                        Text(minLabel)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                    Spacer()
                    if let maxLabel = maxLabel {
                        Text(maxLabel)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }

            // Optional description
            if let description = description {
                Text(description)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
    }
}

// MARK: - Settings Option Card

/// A radio-button style selection card for choosing between exclusive options.
/// Shows icon, title, description, and a selection indicator.
struct SettingsOptionCard: View {
    let title: String
    let description: String
    let icon: String
    let isSelected: Bool
    var isAvailable: Bool = true
    var unavailableLabel: String = "Unavailable"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? AppColors.signalMercury.opacity(0.2) : AppColors.substrateSecondary)
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        if !isAvailable {
                            Text(unavailableLabel)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.accentWarning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(AppColors.accentWarning.opacity(0.2))
                                )
                        }
                    }

                    Text(description)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AppColors.signalMercury)
                } else {
                    Circle()
                        .stroke(AppColors.glassBorder, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.08) : AppColors.substrateSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? AppColors.signalMercury.opacity(0.3) : AppColors.glassBorder, lineWidth: 1)
                    )
            )
            .opacity(!isAvailable ? 0.6 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isAvailable)
    }
}

// MARK: - Settings Status Card

/// A status card with icon, title, subtitle, and optional action button.
/// Supports success, warning, error, and info states.
struct SettingsStatusCard: View {
    enum Status {
        case success, warning, error, info, loading

        var color: Color {
            switch self {
            case .success: return AppColors.accentSuccess
            case .warning: return AppColors.accentWarning
            case .error: return AppColors.accentError
            case .info: return AppColors.signalMercury
            case .loading: return AppColors.signalMercury
            }
        }
    }

    let status: Status
    let icon: String
    let title: String
    let subtitle: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Status icon or loading spinner
            if status == .loading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: status.color))
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(status.color)
                    .frame(width: 24)
            }

            // Title and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(subtitle)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // Optional action button
            if let actionLabel = actionLabel, let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(AppTypography.labelSmall(.medium))
                        .foregroundColor(status.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(status.color, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.substrateSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Settings Feature Row

/// A simple icon + text row for listing features or info items.
/// Useful for "What's Included" or "How it Works" sections.
struct SettingsFeatureRow: View {
    let icon: String
    let text: String
    var iconColor: Color = AppColors.signalMercury

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 20)

            Text(text)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)

            Spacer()
        }
    }
}

// MARK: - Settings Toggle Row

/// A reusable toggle row for settings views.
/// Supports multiple variants:
/// - Simple: title only (no icon, no subtitle)
/// - With description: title + description (no icon)
/// - With icon: title + icon (no subtitle)
/// - Extended: title + icon + subtitle + optional icon color
struct SettingsToggleRow: View {
    let title: String
    var icon: String? = nil
    var subtitle: String? = nil
    var description: String? = nil
    var iconColor: Color? = nil
    @Binding var isOn: Bool

    /// Convenience initializer for title + description (no icon) variant
    init(title: String, description: String, isOn: Binding<Bool>) {
        self.title = title
        self.icon = nil
        self.subtitle = nil
        self.description = description
        self.iconColor = nil
        self._isOn = isOn
    }

    /// Convenience initializer for icon-based variant (with optional subtitle)
    init(title: String, icon: String, subtitle: String? = nil, iconColor: Color? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.description = nil
        self.iconColor = iconColor
        self._isOn = isOn
    }

    var body: some View {
        if let icon = icon {
            // Icon-based layout
            HStack(spacing: subtitle != nil ? 16 : 12) {
                // Icon with optional colored background
                if subtitle != nil {
                    ZStack {
                        Circle()
                            .fill((iconColor ?? AppColors.signalMercury).opacity(0.2))
                            .frame(width: 36, height: 36)

                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundColor(iconColor ?? AppColors.signalMercury)
                    }
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(iconColor ?? AppColors.signalMercury)
                        .frame(width: 32)
                }

                // Title and optional subtitle
                VStack(alignment: .leading, spacing: subtitle != nil ? 4 : 0) {
                    Text(title)
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textPrimary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                Spacer()

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(AppColors.signalMercury)
            }
            .padding(subtitle != nil ? 16 : 12)
            .background(subtitle != nil ? Color.clear : AppColors.substrateSecondary)
            .cornerRadius(subtitle != nil ? 0 : 8)
        } else {
            // Description-based layout (no icon)
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    if let description = description {
                        Text(description)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(AppColors.signalMercury)
        }
    }
}

/// A simple toggle row with just a title (no description or icon).
/// Use for secondary toggles within a section.
struct SettingsToggleRowSimple: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)
        }
        .toggleStyle(.switch)
        .tint(AppColors.signalMercury)
    }
}

// MARK: - Secure Input Field

/// A reusable secure text field with show/hide toggle.
/// Used for API keys, passwords, and other sensitive inputs.
struct SecureInputField: View {
    let placeholder: String
    @Binding var text: String
    var isDisabled: Bool = false
    var hint: String? = nil

    @State private var isShowingText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isShowingText {
                    TextField(placeholder, text: $text)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(AppColors.textPrimary)
                        .disabled(isDisabled)
                } else {
                    SecureField(placeholder, text: $text)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(AppColors.textPrimary)
                        .disabled(isDisabled)
                }

                Button(action: { isShowingText.toggle() }) {
                    Image(systemName: isShowingText ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isDisabled)

                Button(action: {
                    #if os(iOS)
                    if let pastedText = UIPasteboard.general.string {
                        text = pastedText
                    }
                    #elseif os(macOS)
                    if let pastedText = NSPasteboard.general.string(forType: .string) {
                        text = pastedText
                    }
                    #endif
                }) {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isDisabled)
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)

            if let hint = hint {
                Text(hint)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
    }
}

// MARK: - Configuration Status Badge

/// A status badge showing configured/not configured state.
/// Used for API keys, integrations, etc.
struct ConfigurationStatusBadge: View {
    let isConfigured: Bool
    var isRequired: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if isConfigured {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.accentSuccess)
                Text("Configured")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.accentSuccess)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(isRequired ? AppColors.accentError : AppColors.accentWarning)
                Text(isRequired ? "Required" : "Not Configured")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(isRequired ? AppColors.accentError : AppColors.accentWarning)
            }
        }
    }
}

// MARK: - Info Banner

/// An informational banner with icon, title, and message.
/// Enhanced version of SettingsInfoBanner with title + message support.
struct InfoBanner: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(AppColors.signalMercury)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(message)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(AppColors.signalMercury.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Empty State View

/// A generic empty state view with icon, title, and message.
/// Used when lists or sections have no content.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)

            Text(title)
                .font(AppTypography.bodyMedium(.medium))
                .foregroundColor(AppColors.textPrimary)

            Text(message)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Custom Text Field Style

/// A reusable text field style for settings forms.
/// Provides consistent styling with background, border, and padding.
struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(AppColors.substratePrimary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.glassBorder, lineWidth: 1)
            )
            .font(AppTypography.bodyMedium())
            .foregroundColor(AppColors.textPrimary)
    }
}

// MARK: - Expandable Settings Section

/// A header state for expandable sections with multi-select capability.
enum ExpandableSectionState {
    case allEnabled
    case partiallyEnabled
    case allDisabled
}

/// An expandable/collapsible section with header, optional bulk toggle, and child content.
/// Use for grouped items like tool categories or memory types.
struct ExpandableSettingsSection<Content: View>: View {
    let title: String
    let icon: String
    var count: String? = nil
    var state: ExpandableSectionState? = nil
    var onStateToggle: ((Bool) -> Void)? = nil
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Optional multi-state toggle
                    if let state = state, let onToggle = onStateToggle {
                        Button(action: {
                            onToggle(state != .allEnabled)
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(stateColor(state))
                                    .frame(width: 24, height: 24)

                                if state != .allDisabled {
                                    Image(systemName: state == .allEnabled ? "checkmark" : "minus")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Icon
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(state != .allDisabled ? AppColors.signalMercury : AppColors.textTertiary)
                        .frame(width: 24)

                    // Title
                    Text(title)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    // Optional count badge
                    if let count = count {
                        Text(count)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Spacer()

                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Content
            if isExpanded {
                content
                    .padding(.vertical, 8)
                    .background(AppColors.substrateTertiary.opacity(0.5))
                    .cornerRadius(8)
                    .padding(.top, 4)
            }
        }
    }

    private func stateColor(_ state: ExpandableSectionState) -> Color {
        switch state {
        case .allEnabled: return AppColors.signalLichen
        case .partiallyEnabled: return AppColors.signalCopper
        case .allDisabled: return AppColors.textDisabled.opacity(0.3)
        }
    }
}

// MARK: - Unified Model Picker (Abstracted)

/// A flexible, reusable model selection picker that works across different contexts.
/// Supports both global settings and chat-specific use cases with optional context filtering.
///
/// For global settings (no context filtering):
/// ```swift
/// UnifiedModelPicker(
///     provider: currentProvider,
///     selectedModel: $selectedModel,
///     customProviderIndex: providerIndex,
///     showInfoCard: true
/// )
/// ```
///
/// For chat-specific settings (with context filtering):
/// ```swift
/// UnifiedModelPicker(
///     provider: selectedProvider,
///     selectedModel: $selectedModel,
///     estimatedTokens: estimatedTokens,
///     showInsufficientModels: true,
///     showInfoCard: false,
///     onModelSelected: { model in
///         selectModel(model)
///     }
/// )
/// ```
struct UnifiedModelPicker: View {
    // Provider Configuration
    let provider: UnifiedProvider?
    var customProviderIndex: Int = 1
    
    // Selection State
    @Binding var selectedModel: UnifiedModel?
    
    // Context Filtering (optional)
    var estimatedTokens: Int? = nil
    var showInsufficientModels: Bool = false
    
    // UI Configuration
    var showInfoCard: Bool = false
    
    // Callbacks
    var onModelSelected: ((UnifiedModel) -> Void)? = nil

    private var availableModels: [UnifiedModel] {
        guard let provider = provider else { return [] }
        return provider.availableModels(customProviderIndex: customProviderIndex)
    }

    private var currentModel: UnifiedModel? {
        selectedModel ?? availableModels.first
    }

    private var validModels: [UnifiedModel] {
        guard let estimatedTokens = estimatedTokens, estimatedTokens > 0 else {
            return availableModels
        }
        return availableModels.filter { $0.contextWindow >= estimatedTokens }
    }

    private var insufficientModels: [UnifiedModel] {
        guard let estimatedTokens = estimatedTokens, estimatedTokens > 0 else {
            return []
        }
        return availableModels.filter { $0.contextWindow < estimatedTokens }
    }

    private var pickerIcon: String {
        if let model = currentModel {
            if model.modalities.contains("vision") {
                return "eye.circle"
            }
        }
        return "brain.head.profile"
    }

    private var displayedModels: [UnifiedModel] {
        if showInsufficientModels {
            return validModels + insufficientModels
        }
        return validModels
    }

    var body: some View {
        VStack(spacing: 12) {
            StyledMenuPicker(
                icon: pickerIcon,
                title: currentModel?.name ?? "Select Model",
                selection: Binding(
                    get: { currentModel?.id ?? "" },
                    set: { newModelId in
                        if let model = availableModels.first(where: { $0.id == newModelId }) {
                            selectedModel = model
                            onModelSelected?(model)
                        }
                    }
                )
            ) {
                #if os(macOS)
                macOSModelMenu(
                    validModels: validModels,
                    insufficientModels: insufficientModels
                )
                #else
                iOSModelMenu(
                    validModels: validModels,
                    insufficientModels: insufficientModels
                )
                #endif
            }

            // Optional model info card
            if showInfoCard, let model = currentModel {
                UnifiedModelInfoCard(model: model)
            }
        }
    }

    // MARK: - macOS Menu

    #if os(macOS)
    @ViewBuilder
    private func macOSModelMenu(
        validModels: [UnifiedModel],
        insufficientModels: [UnifiedModel]
    ) -> some View {
        ForEach(validModels) { model in
            MenuButtonItem(
                id: model.id,
                label: model.name,
                isSelected: currentModel?.id == model.id
            ) {
                selectedModel = model
                onModelSelected?(model)
            }
        }

        if showInsufficientModels && !validModels.isEmpty && !insufficientModels.isEmpty {
            Section("Insufficient Context") {
                ForEach(insufficientModels) { model in
                    Button {
                        selectedModel = model
                        onModelSelected?(model)
                    } label: {
                        Text("\(model.name) (needs \(model.contextWindow / 1000)K)")
                    }
                    .disabled(true)
                }
            }
        }
    }
    #endif

    // MARK: - iOS Menu

    #if !os(macOS)
    @ViewBuilder
    private func iOSModelMenu(
        validModels: [UnifiedModel],
        insufficientModels: [UnifiedModel]
    ) -> some View {
        ForEach(validModels) { model in
            Text(model.name).tag(model.id)
        }

        if showInsufficientModels && !validModels.isEmpty && !insufficientModels.isEmpty {
            Section("Insufficient Context") {
                ForEach(insufficientModels) { model in
                    Text("\(model.name) (needs \(model.contextWindow / 1000)K)")
                        .tag(model.id)
                        .foregroundColor(AppColors.textDisabled)
                }
            }
        }
    }
    #endif
}

// MARK: - Legacy Unified Model Selection Picker (Deprecated)

/// A complete model selection picker that uses UnifiedModelRegistry.
/// Supports both built-in providers and custom providers.
///
/// Usage:
/// ```swift
/// UnifiedModelSelectionPicker(
///     provider: currentProvider,
///     selectedModel: $selectedModel,
///     customProviderIndex: providerIndex
/// )
/// ```
///
/// Note: Consider using UnifiedModelPicker instead for more flexibility.
struct UnifiedModelSelectionPicker: View {
    let provider: UnifiedProvider
    @Binding var selectedModelId: String
    var customProviderIndex: Int = 1
    var onModelSelected: ((UnifiedModel) -> Void)? = nil

    private var availableModels: [UnifiedModel] {
        provider.availableModels(customProviderIndex: customProviderIndex)
    }

    private var selectedModel: UnifiedModel? {
        availableModels.first { $0.id == selectedModelId || $0.modelCode == selectedModelId }
    }

    private var pickerIcon: String {
        if let model = selectedModel {
            if model.modalities.contains("vision") {
                return "eye.circle"
            }
        }
        return "brain.head.profile"
    }

    var body: some View {
        StyledMenuPicker(
            icon: pickerIcon,
            title: selectedModel?.name ?? "Select a model",
            selection: $selectedModelId
        ) {
            #if os(macOS)
            ForEach(availableModels) { model in
                MenuButtonItem(
                    id: model.id,
                    label: model.name,
                    isSelected: selectedModelId == model.id || selectedModelId == model.modelCode
                ) {
                    selectedModelId = model.id
                    onModelSelected?(model)
                }
            }
            #else
            ForEach(availableModels) { model in
                Text(model.name).tag(model.id)
            }
            #endif
        }
    }
}

// MARK: - Unified Model Info Card

/// Displays detailed information about a selected model.
/// Shows name, description, context window, modalities, and pricing.
///
/// Usage:
/// ```swift
/// if let model = selectedModel {
///     UnifiedModelInfoCard(model: model)
/// }
/// ```
struct UnifiedModelInfoCard: View {
    let model: UnifiedModel
    var isInteractive: Bool = false
    var onTap: (() -> Void)? = nil

    private var isVision: Bool {
        model.modalities.contains("vision") || model.modalities.contains("image")
    }

    private var isAudio: Bool {
        model.modalities.contains("audio")
    }

    private var modelIcon: String {
        if isVision { return "eye.circle.fill" }
        if isAudio { return "waveform.circle.fill" }
        return "cpu"
    }

    var body: some View {
        let content = HStack(spacing: 12) {
            Image(systemName: modelIcon)
                .font(.system(size: 24))
                .foregroundColor(AppColors.signalMercury)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    // Modality badges
                    if isVision {
                        modelBadge("Vision", color: AppColors.signalLichen)
                    }
                    if isAudio {
                        modelBadge("Audio", color: AppColors.signalCopper)
                    }
                }

                Text(model.description)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)

                // Pricing row
                if let pricing = model.pricing {
                    pricingRow(pricing.formattedPricing())
                } else if case .builtIn(let aiModel) = model {
                    if let pricingText = builtInPricingText(for: aiModel) {
                        pricingRow(pricingText)
                    }
                }

                // Stats row
                HStack(spacing: 12) {
                    Label("\(model.contextWindow / 1000)K context", systemImage: "brain.head.profile")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    if case .builtIn(let aiModel) = model {
                        if aiModel.provider == .localMLX || aiModel.provider == .appleFoundation {
                            Label("Private & Free", systemImage: "lock.shield")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                }
            }

            Spacer()

            if isInteractive {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.substrateSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
        )

        if isInteractive, let onTap = onTap {
            Button(action: onTap) {
                content
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            content
        }
    }

    private func modelBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(AppTypography.labelSmall())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    private func pricingRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "dollarsign.circle")
                .foregroundColor(AppColors.textTertiary)
            Text(text)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
                .lineLimit(1)
        }
    }

    private func builtInPricingText(for model: AIModel) -> String? {
        if let key = PricingKeyResolver.canonicalKey(for: model.id) ?? PricingKeyResolver.canonicalKey(for: model.name) {
            let pricing = PricingRegistry.price(for: key)
            var parts: [String] = []
            parts.append(String(format: "$%.2f in / $%.2f out per 1M tokens", pricing.inputPerMTokUSD, pricing.outputPerMTokUSD))
            if let cached = pricing.cachedInputPerMTokUSD {
                parts.append(String(format: "cached: $%.2f", cached))
            }
            return parts.joined(separator: " · ")
        }
        return nil
    }
}

// MARK: - Model Selection Row (Selectable)

/// A selectable model row for use in lists or pickers.
/// Similar to UnifiedModelInfoCard but with selection state.
struct ModelSelectionRow: View {
    let model: UnifiedModel
    let isSelected: Bool
    let action: () -> Void

    private var isVision: Bool {
        model.modalities.contains("vision") || model.modalities.contains("image")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(model.description)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)

                    // Pricing
                    if let customPricing = model.pricing {
                        HStack(spacing: 8) {
                            Image(systemName: "dollarsign.circle")
                                .foregroundColor(AppColors.textTertiary)
                            Text(customPricing.formattedPricing())
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                                .lineLimit(1)
                        }
                    } else if case .builtIn(let aiModel) = model {
                        if let pricingText = builtInPricingText(for: aiModel) {
                            HStack(spacing: 8) {
                                Image(systemName: "dollarsign.circle")
                                    .foregroundColor(AppColors.textTertiary)
                                Text(pricingText)
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Label(
                            String(format: "%.0fK context", Double(model.contextWindow) / 1000),
                            systemImage: "brain.head.profile"
                        )
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                        if isVision {
                            Label("Vision", systemImage: "eye")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.signalLichen)
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.signalMercury)
                        .font(.system(size: 20))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.1) : AppColors.substrateSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? AppColors.signalMercury : AppColors.glassBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func builtInPricingText(for model: AIModel) -> String? {
        if let key = PricingKeyResolver.canonicalKey(for: model.id) ?? PricingKeyResolver.canonicalKey(for: model.name) {
            let pricing = PricingRegistry.price(for: key)
            var parts: [String] = []
            parts.append(String(format: "$%.2f in / $%.2f out per 1M tokens", pricing.inputPerMTokUSD, pricing.outputPerMTokUSD))
            if let cached = pricing.cachedInputPerMTokUSD {
                parts.append(String(format: "cached: $%.2f", cached))
            }
            return parts.joined(separator: " · ")
        }
        return nil
    }
}

// MARK: - Provider Selection Section

/// A reusable provider selection section with sovereignty restrictions support.
/// Use this when you only need provider selection without model selection.
///
/// Usage:
/// ```swift
/// ProviderSelectionSection(
///     viewModel: settingsViewModel,
///     showingNegotiationSheet: $showingSheet
/// )
/// ```
struct ProviderSelectionSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var showingNegotiationSheet: Bool

    private var currentProvider: UnifiedProvider? {
        let allProviders = viewModel.selectableUnifiedProviders()
        return viewModel.currentUnifiedProvider().flatMap { provider in
            if allProviders.contains(where: { $0.id == provider.id }) {
                return provider
            }
            return viewModel.fallbackUnifiedProvider()
        } ?? viewModel.fallbackUnifiedProvider()
    }

    var body: some View {
        GeneralSettingsSection(title: "AI Provider") {
            let allProviders = viewModel.selectableUnifiedProviders()
            let isProviderChangeAllowed = SovereigntyService.shared.isProviderChangeAllowed()
            let providerRestrictionReason = SovereigntyService.shared.providerChangeRestrictionReason()

            // Show restriction banner if provider changes are restricted
            if !isProviderChangeAllowed, let reason = providerRestrictionReason {
                CovenantRestrictionBanner(
                    icon: "lock.shield",
                    message: reason,
                    actionLabel: "Renegotiate",
                    action: {
                        showingNegotiationSheet = true
                    }
                )
            }

            StyledMenuPicker(
                icon: currentProvider?.isCustom == true ? "server.rack" : "cpu.fill",
                title: currentProvider?.displayName ?? "Select Provider",
                selection: Binding(
                    get: { currentProvider?.id ?? "builtin_anthropic" },
                    set: { newProviderId in
                        if let selectedProvider = allProviders.first(where: { $0.id == newProviderId }) {
                            Task {
                                await viewModel.selectUnifiedProvider(selectedProvider)
                            }
                        }
                    }
                )
            ) {
                #if os(macOS)
                Section("Built-in Providers") {
                    ForEach(AIProvider.allCases.filter { viewModel.isBuiltInProviderSelectable($0) }) { aiProvider in
                        MenuButtonItem(
                            id: "builtin_\(aiProvider.rawValue)",
                            label: aiProvider.displayName,
                            isSelected: currentProvider?.id == "builtin_\(aiProvider.rawValue)"
                        ) {
                            if let selected = allProviders.first(where: { $0.id == "builtin_\(aiProvider.rawValue)" }) {
                                Task { await viewModel.selectUnifiedProvider(selected) }
                            }
                        }
                    }
                }

                let selectableCustomProviders = viewModel.settings.customProviders.filter { viewModel.isCustomProviderSelectable($0.id) }
                if !selectableCustomProviders.isEmpty {
                    Section("Custom Providers") {
                        ForEach(selectableCustomProviders) { customProvider in
                            MenuButtonItem(
                                id: "custom_\(customProvider.id.uuidString)",
                                label: customProvider.providerName,
                                isSelected: currentProvider?.id == "custom_\(customProvider.id.uuidString)"
                            ) {
                                if let selected = allProviders.first(where: { $0.id == "custom_\(customProvider.id.uuidString)" }) {
                                    Task { await viewModel.selectUnifiedProvider(selected) }
                                }
                            }
                        }
                    }
                }
                #else
                Section("Built-in Providers") {
                    ForEach(AIProvider.allCases.filter { viewModel.isBuiltInProviderSelectable($0) }) { aiProvider in
                        Text(aiProvider.displayName).tag("builtin_\(aiProvider.rawValue)")
                    }
                }

                let selectableCustomProviders = viewModel.settings.customProviders.filter { viewModel.isCustomProviderSelectable($0.id) }
                if !selectableCustomProviders.isEmpty {
                    Section("Custom Providers") {
                        ForEach(selectableCustomProviders) { customProvider in
                            Text(customProvider.providerName).tag("custom_\(customProvider.id.uuidString)")
                        }
                    }
                }
                #endif
            }
            .disabled(!isProviderChangeAllowed)
            .opacity(isProviderChangeAllowed ? 1.0 : 0.6)
        }
    }
}

// MARK: - Model Selection Section

/// A reusable model selection section that handles both standard and MLX providers.
/// Automatically shows the appropriate UI based on the selected provider.
///
/// Usage:
/// ```swift
/// ModelSelectionSection(viewModel: settingsViewModel)
/// ```
struct ModelSelectionSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    var showInfoCard: Bool = true

    private var currentProvider: UnifiedProvider? {
        viewModel.currentUnifiedProvider()
    }

    private var currentModel: UnifiedModel? {
        viewModel.currentUnifiedModel()
    }

    private var providerIndex: Int {
        viewModel.settings.customProviders.firstIndex(where: { $0.id == viewModel.settings.selectedCustomProviderId }) ?? 0
    }

    var body: some View {
        GeneralSettingsSection(title: "Model") {
            if let provider = currentProvider {
                // Check if this is the MLX provider
                if provider.id == "builtin_localMLX" {
                    MLXModelSelectionContent(viewModel: viewModel)
                } else {
                    StandardModelSelectionContent(
                        viewModel: viewModel,
                        provider: provider,
                        providerIndex: providerIndex,
                        showInfoCard: showInfoCard
                    )
                }
            }
        }
    }
}

// MARK: - MLX Model Selection Content

/// Content view for MLX model selection with manage link.
struct MLXModelSelectionContent: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var mlxModels: [AIModel] {
        viewModel.allMLXModels()
    }

    private var selectedId: String {
        viewModel.selectedMLXModelId()
    }

    private var selectedModel: AIModel? {
        mlxModels.first { $0.id == selectedId }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Model picker dropdown
            StyledMenuPicker(
                icon: selectedModel?.modalities.contains("vision") == true ? "eye.circle" : "cpu",
                title: selectedModel?.name ?? LocalMLXModel.defaultModel.displayName,
                selection: Binding(
                    get: { selectedId },
                    set: { newModelId in
                        Task {
                            await viewModel.selectMLXModel(repoId: newModelId)
                        }
                    }
                )
            ) {
                #if os(macOS)
                ForEach(mlxModels) { model in
                    MenuButtonItem(
                        id: model.id,
                        label: model.name,
                        isSelected: selectedId == model.id
                    ) {
                        Task { await viewModel.selectMLXModel(repoId: model.id) }
                    }
                }
                #else
                ForEach(mlxModels) { model in
                    Text(model.name).tag(model.id)
                }
                #endif
            }

            // Selected model info card
            if let model = selectedModel {
                MLXModelInfoCard(model: model)
            }

            // Manage Models link
            NavigationLink {
                SettingsSubviewContainer {
                    ScrollView {
                        MLXModelManagementView(viewModel: viewModel)
                            .padding()
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16))
                        .foregroundColor(AppColors.signalMercury)

                    Text("Manage Models")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Text("\(viewModel.settings.userMLXModels.count + LocalMLXModel.allCases.count) available")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Standard Model Selection Content

/// Content view for standard (non-MLX) model selection.
/// Now uses the abstracted UnifiedModelPicker component.
struct StandardModelSelectionContent: View {
    @ObservedObject var viewModel: SettingsViewModel
    let provider: UnifiedProvider
    let providerIndex: Int
    var showInfoCard: Bool = true

    private var currentModel: UnifiedModel? {
        viewModel.currentUnifiedModel()
    }

    var body: some View {
        UnifiedModelPicker(
            provider: provider,
            customProviderIndex: providerIndex + 1,
            selectedModel: Binding(
                get: { currentModel },
                set: { newModel in
                    if let model = newModel {
                        Task {
                            await viewModel.selectUnifiedModel(model)
                        }
                    }
                }
            ),
            
            estimatedTokens: nil, // No context filtering for global settings
            showInsufficientModels: false,
            showInfoCard: showInfoCard
        )
    }
}

// MARK: - MLX Model Info Card

/// Displays detailed information about a selected MLX model.
/// Shows name, description, context window, modalities, and privacy info.
struct MLXModelInfoCard: View {
    let model: AIModel

    private var isBundled: Bool {
        model.id == LocalMLXModel.defaultModel.rawValue
    }

    private var isVision: Bool {
        model.modalities.contains("vision")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isVision ? "eye.circle.fill" : "cpu")
                .font(.system(size: 24))
                .foregroundColor(AppColors.signalMercury)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(AppTypography.bodyMedium(.medium))
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

                    if isVision {
                        Text("Vision")
                            .font(AppTypography.labelSmall())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.signalLichen.opacity(0.2))
                            .foregroundColor(AppColors.signalLichen)
                            .cornerRadius(4)
                    }
                }

                Text(model.description)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label("\(model.contextWindow / 1000)K context", systemImage: "brain.head.profile")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    Label("Private & Free", systemImage: "lock.shield")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.substrateSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Gender Filter Button

/// A simple button for filtering by gender in voice pickers.
/// Shows selected state with highlighted background.
struct GenderFilterButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(AppTypography.labelSmall())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? AppColors.signalMercury.opacity(0.2) : Color.clear)
                )
                .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Provider and Model Selection Section (Combined)

/// A complete section for selecting both provider and model.
/// Combines provider picker with model picker and info card.
///
/// Usage:
/// ```swift
/// ProviderModelSelectionSection(
///     viewModel: settingsViewModel,
///     sectionTitle: "AI Provider & Model"
/// )
/// ```
struct ProviderModelSelectionSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    var sectionTitle: String = "AI Configuration"
    var showProviderPicker: Bool = true
    var showModelPicker: Bool = true
    var showModelInfoCard: Bool = true

    @State private var showingNegotiationSheet = false

    private var currentProvider: UnifiedProvider? {
        viewModel.currentUnifiedProvider()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Provider Selection
            if showProviderPicker {
                ProviderSelectionSection(
                    viewModel: viewModel,
                    showingNegotiationSheet: $showingNegotiationSheet
                )
            }

            // Model Selection
            if showModelPicker, currentProvider != nil {
                ModelSelectionSection(viewModel: viewModel, showInfoCard: showModelInfoCard)
            }
        }
        .sheet(isPresented: $showingNegotiationSheet) {
            CovenantNegotiationView(preselectedCategory: .providerChange)
                #if os(macOS)
                .frame(minWidth: 550, idealWidth: 650, minHeight: 600, idealHeight: 800)
                #endif
        }
    }
}
