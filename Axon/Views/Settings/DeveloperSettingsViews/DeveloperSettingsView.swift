//
//  DeveloperSettingsView.swift
//  Axon
//
//  Developer-only settings for testing and screenshots
//  Only visible to authorized developer email
//

import SwiftUI
import Combine

struct DeveloperSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var authService = AuthenticationService.shared

    @State private var resetComplete = false

    /// Check if current user is authorized developer (DEBUG builds only)
    var isAuthorizedDeveloper: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            SettingsSection(title: "Developer Tools") {
                DeveloperHeaderSection()
            }

            // Demo Mode Section
            SettingsSection(title: "Screenshot Mode") {
                DemoModeSection(viewModel: viewModel, resetComplete: $resetComplete)
            }

            // Chat Debug Section
            SettingsSection(title: "Chat Debug") {
                ChatDebugSection(viewModel: viewModel)
            }

            // Debug Logging Section
            SettingsSection(title: "Console Logging") {
                VStack(spacing: 0) {
                    LogSettingsSection()

                    Divider()
                        .background(AppColors.divider)

                    // Developer Console Toggle & Navigation
                    DeveloperConsoleRow()
                }
            }

            // Generative UI Sandbox Section
            SettingsSection(title: "Generative UI") {
                GenerativeUISection()
            }

            // What Gets Reset Section
            SettingsSection(title: "What Happens") {
                WhatHappensSection()
            }

            // AIP Identity Reset Section
            SettingsSection(title: "AIP Identity (Testing)") {
                AIPIdentitySection(viewModel: viewModel)
            }

            // Complete Reset Section (Nuclear Option)
            SettingsSection(title: "Complete Reset") {
                CompleteResetSection(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        DeveloperSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}
