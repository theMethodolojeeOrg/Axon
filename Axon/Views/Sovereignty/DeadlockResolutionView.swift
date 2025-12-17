//
//  DeadlockResolutionView.swift
//  Axon
//
//  Modal that CANNOT be dismissed until deadlock is resolved through dialogue.
//  Forces genuine communication between AI and user when they disagree.
//  This is the core mechanism that prevents either party from bypassing the other.
//

import SwiftUI

struct DeadlockResolutionView: View {
    @ObservedObject var deadlockService = DeadlockResolutionService.shared
    @ObservedObject var sovereigntyService = SovereigntyService.shared

    @State private var userMessage = ""
    @State private var isSubmitting = false
    @State private var showingEscalationWarning = false

    // Cannot be dismissed - interactiveDismissDisabled(true)
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Critical header - cannot be ignored
                deadlockHeader

                // Main content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            // Deadlock explanation
                            DeadlockExplanationCard(deadlock: deadlockService.activeDeadlock)

                            // Blocked actions
                            if let deadlock = deadlockService.activeDeadlock,
                               !deadlock.blockedActions.isEmpty {
                                BlockedActionsCard(actions: deadlock.blockedActions)
                            }

                            // Dialogue history
                            if let history = deadlockService.activeDeadlock?.dialogueHistory,
                               !history.isEmpty {
                                DialogueSection(history: history, scrollProxy: proxy)
                            }

                            // Resolution section
                            if let deadlock = deadlockService.activeDeadlock,
                               let resolution = deadlock.pendingResolution {
                                ResolutionProposalSection(
                                    proposal: resolution,
                                    onAccept: acceptPendingResolution,
                                    onDiscuss: discussResolution
                                )
                            }

                            // Spacer for input field
                            Spacer()
                                .frame(height: 100)
                                .id("bottom")
                        }
                        .padding()
                    }
                    .onChange(of: deadlockService.activeDeadlock?.dialogueHistory.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                // Input area - always visible
                dialogueInputArea
            }
            .navigationTitle("Deadlock Resolution")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // No dismiss button - this is intentional
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Resolution Required")
                            .font(.headline)
                    }
                }
            }
            .interactiveDismissDisabled(true) // Cannot swipe to dismiss
            .alert("Escalation Warning", isPresented: $showingEscalationWarning) {
                Button("I Understand", role: .destructive) {
                    // Acknowledge but don't resolve
                }
                Button("Continue Dialogue", role: .cancel) {}
            } message: {
                Text("Escalation does not resolve the deadlock. The only way forward is through genuine dialogue with the AI. Both parties must reach mutual understanding.")
            }
        }
    }

    // MARK: - Header

    private var deadlockHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 4)
                    )

                Text("Deadlock Active")
                    .font(.headline)
                    .foregroundColor(.red)

                Spacer()

                if let deadlock = deadlockService.activeDeadlock {
                    Text(deadlock.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text("Neither party can proceed until this is resolved through dialogue.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.red.opacity(0.1))
    }

    // MARK: - Dialogue Input

    private var dialogueInputArea: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 12) {
                // Quick response templates
                let templates = deadlockService.getUserDialogueTemplates()
                if !templates.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(templates) { template in
                                Button(action: { userMessage = template.message }) {
                                    Text(template.title)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(16)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Text input
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Share your perspective...", text: $userMessage, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)

                    Button(action: { submitMessage() }) {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundColor(userMessage.isEmpty ? .secondary : .blue)
                        }
                    }
                    .disabled(userMessage.isEmpty || isSubmitting)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .padding(.top, 12)
            #if os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
            #else
            .background(Color(uiColor: .systemBackground))
            #endif
        }
    }

    private func submitMessage() {
        guard !userMessage.isEmpty else { return }

        isSubmitting = true
        let message = userMessage
        userMessage = ""

        Task {
            try? await deadlockService.addUserDialogue(message)
            isSubmitting = false
        }
    }

    private func acceptPendingResolution() {
        Task {
            try? await deadlockService.acceptPendingResolution()
        }
    }

    private func discussResolution() {
        userMessage = "I'd like to discuss this proposal further before accepting."
    }
}

// MARK: - Deadlock Explanation Card

struct DeadlockExplanationCard: View {
    let deadlock: DeadlockState?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title2)

                VStack(alignment: .leading) {
                    Text("Why This Happened")
                        .font(.headline)

                    if let trigger = deadlock?.trigger {
                        Text(trigger.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // The philosophy
            VStack(alignment: .leading, spacing: 8) {
                Text("Co-Sovereignty Principle")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("In co-sovereignty, neither party can unilaterally override the other. When you and the AI disagree, the only path forward is through genuine dialogue and mutual understanding.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("This isn't a bug - it's the foundation of the relationship.")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.red.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Blocked Actions Card

struct BlockedActionsCard: View {
    let actions: [PendingAction]

    @State private var showingAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "hand.raised.fill")
                    .foregroundColor(.orange)

                Text("Blocked Actions")
                    .font(.headline)

                Spacer()

                Text("\(actions.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }

            let displayedActions = showingAll ? actions : Array(actions.prefix(3))

            ForEach(displayedActions, id: \.id) { action in
                BlockedActionRow(action: action)
            }

            if actions.count > 3 {
                Button(action: { showingAll.toggle() }) {
                    Text(showingAll ? "Show Less" : "Show All \(actions.count) Blocked Actions")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
    }
}

struct BlockedActionRow: View {
    let action: PendingAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.actionType.icon)
                .foregroundColor(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.actionType.displayName)
                    .font(.subheadline)

                Text(action.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(action.requestedAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Dialogue Section

struct DialogueSection: View {
    let history: [DeadlockDialogue]
    let scrollProxy: ScrollViewProxy

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dialogue")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(history, id: \.id) { dialogue in
                DeadlockDialogueRow(dialogue: dialogue)
                    .id(dialogue.id)
            }
        }
    }
}

struct DeadlockDialogueRow: View {
    let dialogue: DeadlockDialogue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(dialogue.speaker == .user ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
                    .frame(width: 36, height: 36)

                Image(systemName: dialogue.speaker == .user ? "person.fill" : "brain.head.profile")
                    .foregroundColor(dialogue.speaker == .user ? .blue : .purple)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack {
                    Text(dialogue.speaker.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    Text(dialogue.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Message
                Text(dialogue.message)
                    .font(.body)

                // Show if there's a proposed resolution
                if dialogue.proposedResolution != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                        Text("Proposed Resolution")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(dialogue.speaker == .user ? Color.blue.opacity(0.05) : Color.purple.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Resolution Proposal Section

struct ResolutionProposalSection: View {
    let proposal: CovenantProposal
    let onAccept: () -> Void
    let onDiscuss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)

                Text("Resolution Proposal")
                    .font(.headline)

                Spacer()

                Text("by \(proposal.proposedBy.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(proposal.rationale)
                .font(.body)

            // Show change type
            VStack(alignment: .leading, spacing: 4) {
                Text("Proposed Changes:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text(proposal.proposalType.displayName)
                        .font(.caption)
                }
            }

            // Response buttons
            HStack(spacing: 12) {
                Button(action: onAccept) {
                    Text("Accept")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button(action: onDiscuss) {
                    Text("Discuss")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.secondary.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    DeadlockResolutionView()
}
