//
//  JointNegotiationView.swift
//  Axon
//
//  Created by Tom on 2025.
//
//  Multi-step view for joint host + AI consent flow
//

import SwiftUI
import LocalAuthentication

// MARK: - Joint Negotiation View

struct JointNegotiationView: View {
    let request: SharingRequest
    @ObservedObject private var sharingService = GuestSharingService.shared
    @ObservedObject private var consentService = AIShareConsentService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: NegotiationStep = .requestOverview
    @State private var aiAttestation: AIShareAttestation?
    @State private var hostDecision: RequestDecision?
    @State private var modifiedCapabilities: GuestCapabilities?
    @State private var hostMessage: String = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var showingFinalConfirmation = false
    @State private var isInitializing = true

    enum NegotiationStep: Int, CaseIterable {
        case requestOverview = 0
        case aiInput = 1
        case hostResponse = 2
        case resolution = 3
        case confirmation = 4

        var title: String {
            switch self {
            case .requestOverview: return "Request"
            case .aiInput: return "AI Input"
            case .hostResponse: return "Your Response"
            case .resolution: return "Resolution"
            case .confirmation: return "Confirm"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            ProgressStepsView(currentStep: currentStep.rawValue, totalSteps: NegotiationStep.allCases.count)
                .padding()

            if isInitializing {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading request details...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Content based on current step
                ScrollView {
                    VStack(spacing: 24) {
                        switch currentStep {
                        case .requestOverview:
                            RequestOverviewStep(request: request)
                        case .aiInput:
                            AIInputStep(
                                request: request,
                                attestation: aiAttestation,
                                isLoading: consentService.isGenerating
                            )
                        case .hostResponse:
                            HostResponseStep(
                                request: request,
                                aiAttestation: aiAttestation,
                                decision: $hostDecision,
                                capabilities: $modifiedCapabilities,
                                message: $hostMessage
                            )
                        case .resolution:
                            ResolutionStep(
                                request: request,
                                aiAttestation: aiAttestation,
                                hostDecision: hostDecision
                            )
                        case .confirmation:
                            ConfirmationStep(
                                request: request,
                                aiAttestation: aiAttestation,
                                hostDecision: hostDecision,
                                capabilities: modifiedCapabilities ?? GuestCapabilities.standard
                            )
                        }

                        if let error = error {
                            ErrorBanner(message: error)
                        }
                    }
                    .padding()
                }

                // Navigation buttons
                navigationButtons
            }
        }
        .navigationTitle("Review Request")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            // Start negotiation if not already started
            if request.status == .pending {
                do {
                    _ = try await sharingService.startNegotiation(for: request.id)
                } catch {
                    self.error = error.localizedDescription
                }
            }
            // Mark as initialized after a brief delay to ensure view is ready
            isInitializing = false
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            // Back button
            if currentStep != .requestOverview {
                Button {
                    withAnimation {
                        goBack()
                    }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            // Primary action button
            Button {
                Task {
                    await handlePrimaryAction()
                }
            } label: {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    HStack {
                        Text(primaryButtonTitle)
                        Image(systemName: "chevron.right")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || !canProceed)
        }
        .padding()
        .background(.bar)
    }

    private var primaryButtonTitle: String {
        switch currentStep {
        case .requestOverview:
            return "Get AI Input"
        case .aiInput:
            return "Continue"
        case .hostResponse:
            return hostDecision == .decline ? "Decline Request" : "Continue"
        case .resolution:
            return "Finalize"
        case .confirmation:
            return "Create Invitation"
        }
    }

    private var canProceed: Bool {
        switch currentStep {
        case .requestOverview:
            return true
        case .aiInput:
            return aiAttestation != nil
        case .hostResponse:
            return hostDecision != nil
        case .resolution:
            return true
        case .confirmation:
            return true
        }
    }

    // MARK: - Navigation Actions

    private func goBack() {
        if let previousStep = NegotiationStep(rawValue: currentStep.rawValue - 1) {
            currentStep = previousStep
        }
    }

    private func handlePrimaryAction() async {
        isLoading = true
        error = nil

        do {
            switch currentStep {
            case .requestOverview:
                // Get AI attestation
                aiAttestation = try await sharingService.getAIAttestation(for: request)
                withAnimation {
                    currentStep = .aiInput
                }

            case .aiInput:
                withAnimation {
                    currentStep = .hostResponse
                }

            case .hostResponse:
                guard let decision = hostDecision else { return }

                // Submit host response
                let response = HostResponse(
                    decision: decision,
                    grantedCapabilities: modifiedCapabilities ?? GuestCapabilities.standard,
                    grantedDuration: request.requestedDuration,
                    message: hostMessage.isEmpty ? nil : hostMessage
                )

                try await sharingService.submitHostResponse(requestId: request.id, response: response)

                if decision == .decline {
                    // Finalize immediately on decline
                    _ = try await sharingService.finalizeJointDecision(for: request.id)
                    dismiss()
                } else {
                    withAnimation {
                        currentStep = .resolution
                    }
                }

            case .resolution:
                // Check if we need discussion or can proceed
                let jointDecision = try await sharingService.finalizeJointDecision(for: request.id)

                if jointDecision?.requiresDiscussion == true {
                    // Stay on resolution step for discussion
                    error = "You and your AI have different views. Please discuss to reach consensus."
                } else if jointDecision?.isApproved == true {
                    withAnimation {
                        currentStep = .confirmation
                    }
                } else {
                    // Joint decline
                    dismiss()
                }

            case .confirmation:
                // Create invitation with biometric
                let authenticated = await authenticateWithBiometric()
                if authenticated {
                    if let jointDecision = request.jointDecision {
                        if let result = sharingService.createInvitation(from: jointDecision, for: request) {
                            // Show success and share options
                            showingFinalConfirmation = true
                        }
                    }
                    dismiss()
                } else {
                    error = "Authentication required to create invitation"
                }
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func authenticateWithBiometric() async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return true // No biometric available, allow anyway
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to create sharing invitation"
            )
        } catch {
            return false
        }
    }
}

// MARK: - Step Views

struct RequestOverviewStep: View {
    let request: SharingRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 16) {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text(request.guestName.prefix(1).uppercased())
                            .font(.title.bold())
                            .foregroundColor(.blue)
                    )

                VStack(alignment: .leading) {
                    Text(request.guestName)
                        .font(.title2.bold())
                    Text("Requested \(request.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Reason
            VStack(alignment: .leading, spacing: 8) {
                Label("Why they need access", systemImage: "text.quote")
                    .font(.headline)
                Text(request.reason)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
            }

            // Requested capabilities
            VStack(alignment: .leading, spacing: 8) {
                Label("What they're asking for", systemImage: "checklist")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    CapabilityRequestRow(
                        icon: "bubble.left.and.bubble.right",
                        title: "Chat with your AI's context",
                        requested: request.requestedCapabilities.wantsChatWithContext
                    )
                    CapabilityRequestRow(
                        icon: "magnifyingglass",
                        title: "Search your AI's memories",
                        requested: request.requestedCapabilities.wantsMemorySearch
                    )
                    if let topics = request.requestedCapabilities.wantsSpecificTopics, !topics.isEmpty {
                        HStack(alignment: .top) {
                            Image(systemName: "tag")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text("Specific topics:")
                                    .font(.subheadline)
                                Text(topics.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            }

            // Duration
            VStack(alignment: .leading, spacing: 8) {
                Label("Duration requested", systemImage: "clock")
                    .font(.headline)
                Text(request.formattedDuration)
                    .font(.title3.bold())
                    .foregroundColor(.blue)
            }
        }
    }
}

struct CapabilityRequestRow: View {
    let icon: String
    let title: String
    let requested: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(requested ? .blue : .gray)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
            Spacer()
            Image(systemName: requested ? "checkmark.circle.fill" : "circle")
                .foregroundColor(requested ? .green : .gray)
        }
    }
}

struct AIInputStep: View {
    let request: SharingRequest
    let attestation: AIShareAttestation?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title)
                    .foregroundColor(.purple)
                Text("AI's Assessment")
                    .font(.title2.bold())
            }

            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Your AI is analyzing this request...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if let attestation = attestation {
                // Decision badge
                HStack {
                    Image(systemName: attestation.decision.icon)
                        .font(.title2)
                    Text(attestation.decision.displayName)
                        .font(.headline)
                }
                .foregroundColor(attestation.consents ? .green : .orange)
                .padding()
                .background((attestation.consents ? Color.green : Color.orange).opacity(0.15))
                .cornerRadius(12)

                // Reasoning
                VStack(alignment: .leading, spacing: 12) {
                    Text("Summary")
                        .font(.headline)
                    Text(attestation.reasoning.summary)
                        .foregroundColor(.secondary)

                    Divider()

                    Text("Privacy Assessment")
                        .font(.headline)
                    Text(attestation.reasoning.privacyAssessment)
                        .foregroundColor(.secondary)

                    if !attestation.reasoning.recommendations.isEmpty {
                        Divider()

                        Text("Recommendations")
                            .font(.headline)
                        ForEach(attestation.reasoning.recommendations, id: \.self) { rec in
                            HStack(alignment: .top) {
                                Image(systemName: "lightbulb")
                                    .foregroundColor(.yellow)
                                Text(rec)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                // Conditions (if any)
                if let conditions = attestation.conditions, !conditions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Conditions", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                            .foregroundColor(.orange)

                        ForEach(conditions, id: \.self) { condition in
                            HStack(alignment: .top) {
                                Text("•")
                                Text(condition)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }

                // Concerns (if any)
                if let concerns = attestation.concerns, !concerns.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Concerns", systemImage: "exclamationmark.circle")
                            .font(.headline)
                            .foregroundColor(.red)

                        ForEach(concerns, id: \.self) { concern in
                            HStack(alignment: .top) {
                                Text("•")
                                Text(concern)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
    }
}

struct HostResponseStep: View {
    let request: SharingRequest
    let aiAttestation: AIShareAttestation?
    @Binding var decision: RequestDecision?
    @Binding var capabilities: GuestCapabilities?
    @Binding var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "person.fill")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("Your Decision")
                    .font(.title2.bold())
            }

            // Quick decision buttons
            VStack(spacing: 12) {
                if aiAttestation?.consents == true {
                    DecisionButton(
                        title: "Agree with AI",
                        subtitle: "Accept with AI's recommended conditions",
                        icon: "checkmark.circle",
                        color: .green,
                        isSelected: decision == .accept
                    ) {
                        decision = .accept
                        capabilities = aiAttestation?.suggestedModifications ?? GuestCapabilities.standard
                    }
                }

                DecisionButton(
                    title: "Accept",
                    subtitle: "Grant the requested access",
                    icon: "checkmark.circle",
                    color: .green,
                    isSelected: decision == .accept && aiAttestation?.consents != true
                ) {
                    decision = .accept
                    capabilities = GuestCapabilities.standard
                }

                DecisionButton(
                    title: "Counter Offer",
                    subtitle: "Accept with different terms",
                    icon: "arrow.left.arrow.right",
                    color: .orange,
                    isSelected: decision == .counterOffer
                ) {
                    decision = .counterOffer
                }

                DecisionButton(
                    title: "Decline",
                    subtitle: "Don't share with this guest",
                    icon: "xmark.circle",
                    color: .red,
                    isSelected: decision == .decline
                ) {
                    decision = .decline
                }
            }

            // Capability editor for counter offer
            if decision == .counterOffer {
                Divider()

                Text("Customize Capabilities")
                    .font(.headline)

                CapabilityEditorView(capabilities: $capabilities)
            }

            // Optional message
            VStack(alignment: .leading, spacing: 8) {
                Text("Message (optional)")
                    .font(.headline)
                TextField("Add a note for the guest...", text: $message, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
            }
        }
    }
}

struct DecisionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 32)

                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CapabilityEditorView: View {
    @Binding var capabilities: GuestCapabilities?

    private var currentCapabilities: GuestCapabilities {
        capabilities ?? GuestCapabilities.standard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Chat with Context", isOn: Binding(
                get: { currentCapabilities.canChatWithContext },
                set: { newValue in
                    var caps = currentCapabilities
                    capabilities = GuestCapabilities(
                        canChatWithContext: newValue,
                        canQueryMemories: caps.canQueryMemories,
                        maxMemoriesPerQuery: caps.maxMemoriesPerQuery,
                        maxQueriesPerHour: caps.maxQueriesPerHour,
                        allowedMemoryTypes: caps.allowedMemoryTypes,
                        allowedTopics: caps.allowedTopics,
                        excludedTags: caps.excludedTags
                    )
                }
            ))

            Toggle("Search Memories", isOn: Binding(
                get: { currentCapabilities.canQueryMemories },
                set: { newValue in
                    capabilities = GuestCapabilities(
                        canChatWithContext: currentCapabilities.canChatWithContext,
                        canQueryMemories: newValue,
                        maxMemoriesPerQuery: currentCapabilities.maxMemoriesPerQuery,
                        maxQueriesPerHour: currentCapabilities.maxQueriesPerHour,
                        allowedMemoryTypes: currentCapabilities.allowedMemoryTypes,
                        allowedTopics: currentCapabilities.allowedTopics,
                        excludedTags: currentCapabilities.excludedTags
                    )
                }
            ))

            if currentCapabilities.canQueryMemories {
                Stepper("Max \(currentCapabilities.maxMemoriesPerQuery) memories/query", value: Binding(
                    get: { currentCapabilities.maxMemoriesPerQuery },
                    set: { newValue in
                        capabilities = GuestCapabilities(
                            canChatWithContext: currentCapabilities.canChatWithContext,
                            canQueryMemories: currentCapabilities.canQueryMemories,
                            maxMemoriesPerQuery: newValue,
                            maxQueriesPerHour: currentCapabilities.maxQueriesPerHour,
                            allowedMemoryTypes: currentCapabilities.allowedMemoryTypes,
                            allowedTopics: currentCapabilities.allowedTopics,
                            excludedTags: currentCapabilities.excludedTags
                        )
                    }
                ), in: 1...20)

                Stepper("\(currentCapabilities.maxQueriesPerHour) queries/hour", value: Binding(
                    get: { currentCapabilities.maxQueriesPerHour },
                    set: { newValue in
                        capabilities = GuestCapabilities(
                            canChatWithContext: currentCapabilities.canChatWithContext,
                            canQueryMemories: currentCapabilities.canQueryMemories,
                            maxMemoriesPerQuery: currentCapabilities.maxMemoriesPerQuery,
                            maxQueriesPerHour: newValue,
                            allowedMemoryTypes: currentCapabilities.allowedMemoryTypes,
                            allowedTopics: currentCapabilities.allowedTopics,
                            excludedTags: currentCapabilities.excludedTags
                        )
                    }
                ), in: 1...100)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

struct ResolutionStep: View {
    let request: SharingRequest
    let aiAttestation: AIShareAttestation?
    let hostDecision: RequestDecision?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "scale.3d")
                    .font(.title)
                    .foregroundColor(.purple)
                Text("Joint Decision")
                    .font(.title2.bold())
            }

            // Summary cards
            HStack(spacing: 16) {
                SummaryCard(
                    title: "You",
                    icon: "person.fill",
                    decision: hostDecision?.displayName ?? "Pending",
                    color: hostDecision == .accept ? .green : (hostDecision == .decline ? .red : .orange)
                )

                SummaryCard(
                    title: "AI",
                    icon: "brain.head.profile",
                    decision: aiAttestation?.decision.displayName ?? "Pending",
                    color: aiAttestation?.consents == true ? .green : .orange
                )
            }

            // Agreement status
            if let host = hostDecision, let ai = aiAttestation {
                let inAgreement = (host == .accept || host == .counterOffer) == ai.consents

                HStack {
                    Image(systemName: inAgreement ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.title2)
                    Text(inAgreement ? "You're in agreement!" : "Different perspectives")
                        .font(.headline)
                }
                .foregroundColor(inAgreement ? .green : .orange)
                .padding()
                .frame(maxWidth: .infinity)
                .background((inAgreement ? Color.green : Color.orange).opacity(0.15))
                .cornerRadius(12)

                if !inAgreement {
                    Text("You and your AI have different views on this request. You can proceed with your decision, but consider your AI's concerns.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct SummaryCard: View {
    let title: String
    let icon: String
    let decision: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
            Text(title)
                .font(.headline)
            Text(decision)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct ConfirmationStep: View {
    let request: SharingRequest
    let aiAttestation: AIShareAttestation?
    let hostDecision: RequestDecision?
    let capabilities: GuestCapabilities

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title)
                    .foregroundColor(.green)
                Text("Ready to Share")
                    .font(.title2.bold())
            }

            // Summary
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Guest", value: request.guestName)
                LabeledContent("Duration", value: request.formattedDuration)
                Divider()
                Text("Granted Capabilities")
                    .font(.headline)
                CapabilitySummaryView(capabilities: capabilities)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)

            // Consent summary
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "person.fill.checkmark")
                        .foregroundColor(.green)
                    Text("Your consent: \(hostDecision?.displayName ?? "Approved")")
                }
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.green)
                    Text("AI consent: \(aiAttestation?.decision.displayName ?? "Approved")")
                }
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)

            // Final notice
            Text("Authenticate with Face ID or Touch ID to create the sharing invitation.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Supporting Views

struct ProgressStepsView: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color.blue : Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)

                if step < totalSteps - 1 {
                    Rectangle()
                        .fill(step < currentStep ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(height: 2)
                }
            }
        }
        .frame(maxWidth: 200)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        JointNegotiationView(request: SharingRequest(
            guestName: "Alex",
            guestDeviceId: "device-123",
            requestedCapabilities: RequestedCapabilities(
                wantsChatWithContext: true,
                wantsMemorySearch: true,
                wantsSpecificTopics: ["Swift", "iOS development"]
            ),
            requestedDuration: 86400,
            reason: "I'm working on a similar iOS project and could really use some help with SwiftUI patterns you've figured out."
        ))
    }
}
