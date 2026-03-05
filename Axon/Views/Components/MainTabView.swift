//
//  MainTabView.swift
//  Axon
//
//  Main tab navigation for the app
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Conversations Tab
            ConversationListView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(0)

            // Memory Tab
            MemoryListView()
                .tabItem {
                    Label("Memory", systemImage: "brain")
                }
                .tag(1)

            // Settings Tab
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(2)
        }
        .accentColor(AppColors.signalMercury)
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
}
