//
//  MacDetailWithInspector.swift
//  Axon
//
//  macOS-only: wraps the main detail view with a persistent right-side
//  inspector column for code artifacts.
//

import SwiftUI

#if os(macOS)

struct MacDetailWithInspector: View {
    let currentView: MainView
    let selectedConversation: Conversation?
    let startNewChat: () -> Void
    let onConversationCreated: (Conversation) -> Void
    @ObservedObject var presenter: CodeArtifactPresenter

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                AppColors.substratePrimary.ignoresSafeArea()

                switch currentView {
                case .chat:
                    if selectedConversation == nil {
                        MacDetailEmptyStateView(
                            icon: "bubble.left.and.bubble.right",
                            title: "No Chat Selected",
                            message: "Choose a conversation from the sidebar, or start a new one.",
                            primaryActionTitle: "New Chat",
                            primaryAction: startNewChat
                        )
                    } else {
                        ChatContainerView(
                            conversation: selectedConversation,
                            onNewChat: startNewChat,
                            onConversationCreated: onConversationCreated
                        )
                        // Route any code-block artifact presentation up to the root presenter.
                        .environment(\.presentCodeArtifact) { artifact in
                            presenter.present(artifact)
                        }
                    }

                case .memory:
                    MemoryView()

                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Inspector drawer - slides in/out
            if presenter.isOpen {
                CodeArtifactInspectorColumn(presenter: presenter)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: presenter.isOpen)
    }
}

#endif
