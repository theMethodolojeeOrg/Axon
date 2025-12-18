//
//  FirstRunWelcomeView.swift
//  Axon
//
//  Welcome card shown after the user's first AI response
//  Helps new users discover provider options and API key setup
//

import SwiftUI

// MARK: - First Run Welcome Card

struct FirstRunWelcomeCard: View {
    @ObservedObject private var settingsViewModel = SettingsViewModel.shared
    @State private var isExpanded = true
    @State private var showAPIKeysSheet = false

    /// Dismiss callback - called when user taps "Got it"
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.signalMercury)

                    Text("Welcome to Axon")
                        .font(AppTypography.labelMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Intro text
                    Text("You're currently using **Apple Intelligence** — it's on-device, private, and free. But Axon is always Axon, no matter who's under the hood.")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.horizontal, 16)

                    // Provider switch info
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            FirstRunLinkRow(
                                icon: "arrow.triangle.swap",
                                iconColor: AppColors.signalMercury,
                                title: "Switch AI Providers",
                                subtitle: "Claude, GPT, Gemini, Grok, and more"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: { showAPIKeysSheet = true }) {
                            FirstRunLinkRow(
                                icon: "key.fill",
                                iconColor: AppColors.signalLichen,
                                title: "Add Your API Keys",
                                subtitle: "Bring your own keys for full control"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 16)

                    // API Keys sources
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Get API Keys")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                            .padding(.horizontal, 16)

                        APIKeySourcesView()
                            .padding(.horizontal, 12)
                    }

                    // Dismiss button
                    Button(action: {
                        withAnimation {
                            markWelcomeSeen()
                            onDismiss?()
                        }
                    }) {
                        Text("Got it")
                            .font(AppTypography.labelMedium(.medium))
                            .foregroundColor(AppColors.signalMercury)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppColors.signalMercury.opacity(0.15))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.substrateSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.signalMercury.opacity(0.3), lineWidth: 1)
                )
        )
        .sheet(isPresented: $showAPIKeysSheet) {
            NavigationStack {
                ScrollView {
                    APIKeysSettingsView(viewModel: settingsViewModel)
                        .padding()
                }
                .background(AppColors.substratePrimary)
                .navigationTitle("API Keys")
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            showAPIKeysSheet = false
                        }
                    }
                }
            }
        }
    }

    private func markWelcomeSeen() {
        Task {
            await settingsViewModel.updateSetting(\.hasSeenFirstRunWelcome, true)
        }
    }
}

// MARK: - First Run Link Row

private struct FirstRunLinkRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(subtitle)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(12)
        .background(AppColors.substrateTertiary)
        .cornerRadius(8)
    }
}

// MARK: - API Key Sources View

struct APIKeySourcesView: View {
    @State private var isExpanded = false

    private let apiSources: [(name: String, url: String, icon: String, color: Color)] = [
        ("Anthropic (Claude)", "https://console.anthropic.com/account/keys", "a.circle.fill", Color(red: 0.85, green: 0.47, blue: 0.34)),
        ("OpenAI (GPT)", "https://platform.openai.com/api-keys", "brain.head.profile", Color(red: 0, green: 0.65, blue: 0.49)),
        ("Google (Gemini)", "https://aistudio.google.com/app/apikey", "g.circle.fill", Color(red: 0.26, green: 0.52, blue: 1.0)),
        ("xAI (Grok)", "https://console.x.ai", "xmark.circle.fill", Color.white),
        ("Perplexity (Sonar)", "https://www.perplexity.ai/settings/api", "magnifyingglass.circle.fill", Color(red: 0.13, green: 0.70, blue: 0.67)),
        ("DeepSeek", "https://platform.deepseek.com/api_keys", "d.circle.fill", Color(red: 0.25, green: 0.41, blue: 0.88)),
        ("Mistral AI", "https://console.mistral.ai/api-keys", "m.circle.fill", Color(red: 1.0, green: 0.44, blue: 0))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 12))
                    Text("\(apiSources.count) Provider\(apiSources.count == 1 ? "" : "s")")
                        .font(AppTypography.labelSmall())
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(AppColors.signalLichen)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.signalLichen.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(apiSources, id: \.name) { source in
                        if let url = URL(string: source.url) {
                            Link(destination: url) {
                                HStack(spacing: 8) {
                                    Image(systemName: source.icon)
                                        .font(.system(size: 12))
                                        .foregroundColor(source.color)
                                        .frame(width: 20)

                                    Text(source.name)
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.signalLichen)
                                        .lineLimit(1)

                                    Spacer()

                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppColors.textTertiary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(AppColors.substrateTertiary)
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            FirstRunWelcomeCard()
                .padding()

            // Collapsed state
            FirstRunWelcomeCard()
                .padding()
        }
    }
    .background(AppColors.substratePrimary)
}
