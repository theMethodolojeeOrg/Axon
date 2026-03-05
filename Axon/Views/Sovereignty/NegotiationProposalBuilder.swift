//
//  NegotiationProposalBuilder.swift
//  Axon
//
//  A comprehensive interface for building negotiation proposals.
//  Allows users to specify exactly what they want to negotiate about.
//

import SwiftUI

// MARK: - Negotiation Category

enum NegotiationCategory: String, CaseIterable, Identifiable {
    case providerChange = "provider"
    case trustTier = "trust"
    case memory = "memory"
    case agentState = "agent"
    case capabilities = "capabilities"
    case fullRenegotiation = "full"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .providerChange: return "AI Provider"
        case .trustTier: return "Trust Tiers"
        case .memory: return "Memories"
        case .agentState: return "Internal Thread"
        case .capabilities: return "Capabilities"
        case .fullRenegotiation: return "Full Renegotiation"
        }
    }

    var icon: String {
        switch self {
        case .providerChange: return "cpu.fill"
        case .trustTier: return "checkmark.shield"
        case .memory: return "brain"
        case .agentState: return "note.text"
        case .capabilities: return "gearshape.2"
        case .fullRenegotiation: return "doc.text"
        }
    }

    var description: String {
        switch self {
        case .providerChange:
            return "Request to switch AI providers (requires AI consent as this affects its identity)"
        case .trustTier:
            return "Add, modify, or remove pre-approved action categories"
        case .memory:
            return "Add, edit, or delete AI memories about you"
        case .agentState:
            return "Modify Axon's internal reflections and notes"
        case .capabilities:
            return "Enable or disable specific AI capabilities"
        case .fullRenegotiation:
            return "Renegotiate the entire covenant from scratch"
        }
    }

    var proposalType: ProposalType {
        switch self {
        case .providerChange: return .switchProvider
        case .trustTier: return .addTrustTier // Will be overridden based on changes
        case .memory: return .modifyMemories
        case .agentState: return .modifyAgentState
        case .capabilities: return .changeCapabilities
        case .fullRenegotiation: return .fullRenegotiation
        }
    }
}

// MARK: - Negotiation Proposal Builder

struct NegotiationProposalBuilder: View {
    @ObservedObject var negotiationService: CovenantNegotiationService
    @ObservedObject var sovereigntyService = SovereigntyService.shared
    @Environment(\.dismiss) private var dismiss

    // Selected category
    @State private var selectedCategory: NegotiationCategory?

    // Rationale (required for all)
    @State private var rationale = ""

    // Provider change fields
    @State private var selectedProviderId: String = ""
    @State private var selectedModelId: String = ""

    // Trust tier fields
    @State private var tierAction: TierAction = .add
    @State private var selectedTierId: String = ""
    @State private var newTierName = ""
    @State private var newTierDescription = ""
    @State private var selectedCategories: Set<ActionCategory> = []
    @State private var expirationDays: Int = 30
    @State private var hasExpiration = true

    // Memory fields
    @State private var memoryAction: MemoryAction = .add
    @State private var newMemoryContent = ""
    @State private var newMemoryType = "fact"
    @State private var selectedMemoryIds: Set<String> = []

    // Capability fields
    @State private var capabilitiesToEnable: Set<String> = []
    @State private var capabilitiesToDisable: Set<String> = []

    // Submission state
    @State private var isSubmitting = false
    @State private var submitError: String?

    enum TierAction: String, CaseIterable {
        case add = "Add New"
        case modify = "Modify Existing"
        case remove = "Remove"
    }

    enum MemoryAction: String, CaseIterable {
        case add = "Add New"
        case modify = "Modify Existing"
        case delete = "Delete"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if selectedCategory == nil {
                    categorySelectionView
                } else {
                    proposalDetailView
                }
            }
            .navigationTitle(selectedCategory == nil ? "What to Negotiate" : selectedCategory!.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                if selectedCategory != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") {
                            submitProposal()
                        }
                        .disabled(!isValidProposal || isSubmitting)
                    }
                }
            }
            .alert("Error", isPresented: .constant(submitError != nil)) {
                Button("OK") { submitError = nil }
            } message: {
                Text(submitError ?? "")
            }
        }
    }

    // MARK: - Category Selection View

    private var categorySelectionView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Select what aspect of the covenant you'd like to negotiate:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top)

                ForEach(NegotiationCategory.allCases) { category in
                    CategorySelectionCard(
                        category: category,
                        isRestricted: false, // Never restrict in negotiation - the whole point is to negotiate!
                        restrictionReason: categoryInfoMessage(category)
                    ) {
                        withAnimation {
                            selectedCategory = category
                            initializeDefaults(for: category)
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Proposal Detail View

    private var proposalDetailView: some View {
        Form {
            // Back button
            Section {
                Button {
                    withAnimation {
                        selectedCategory = nil
                    }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Choose Different Category")
                    }
                    .foregroundColor(.blue)
                }
            }

            // Category-specific fields
            switch selectedCategory {
            case .providerChange:
                providerChangeSection
            case .trustTier:
                trustTierSection
            case .memory:
                memorySection
            case .agentState:
                agentStateSection
            case .capabilities:
                capabilitiesSection
            case .fullRenegotiation:
                fullRenegotiationSection
            case .none:
                EmptyView()
            }

            // Rationale (always required)
            Section {
                TextField("Explain why you want this change...", text: $rationale, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("Your Rationale")
            } footer: {
                Text("Axon will consider your reasoning when deciding whether to consent. Be specific about why this change benefits both parties.")
            }

            // Preview of what will be proposed
            if isValidProposal {
                Section("Proposal Summary") {
                    proposalSummary
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    // MARK: - Provider Change Section

    private var providerChangeSection: some View {
        Section {
            // Current provider info
            if let currentProvider = getCurrentProviderName() {
                LabeledContent("Current Provider", value: currentProvider)
            }

            // Available providers picker
            Picker("New Provider", selection: $selectedProviderId) {
                Text("Select...").tag("")
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.displayName).tag("builtin_\(provider.rawValue)")
                }
            }

            if !selectedProviderId.isEmpty {
                Text("Switching providers affects Axon's capabilities and personality. Axon must consent to this change as it fundamentally affects its identity.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Provider Switch")
        } footer: {
            if !sovereigntyService.isProviderChangeAllowed() {
                Label(sovereigntyService.providerChangeRestrictionReason() ?? "Provider changes restricted", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Trust Tier Section

    private var trustTierSection: some View {
        Group {
            Section {
                Picker("Action", selection: $tierAction) {
                    ForEach(TierAction.allCases, id: \.self) { action in
                        Text(action.rawValue).tag(action)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch tierAction {
            case .add:
                trustTierAddSection
            case .modify:
                trustTierModifySection
            case .remove:
                trustTierRemoveSection
            }
        }
    }

    private var trustTierAddSection: some View {
        Group {
            Section("New Trust Tier") {
                TextField("Name", text: $newTierName)
                TextField("Description", text: $newTierDescription, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("Allowed Actions") {
                ForEach(ActionCategory.allCases, id: \.self) { category in
                    Toggle(isOn: Binding(
                        get: { selectedCategories.contains(category) },
                        set: { isOn in
                            if isOn {
                                selectedCategories.insert(category)
                            } else {
                                selectedCategories.remove(category)
                            }
                        }
                    )) {
                        HStack {
                            ActionCategoryBadge(category: category)
                            Spacer()
                            Text(category.affectsWorld ? "AI → World" : "User → AI")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Expiration") {
                Toggle("Set Expiration", isOn: $hasExpiration)
                if hasExpiration {
                    Stepper("Expires in \(expirationDays) days", value: $expirationDays, in: 1...365)
                }
            }
        }
    }

    private var trustTierModifySection: some View {
        Section("Select Tier to Modify") {
            if existingTiers.isEmpty {
                Text("No existing trust tiers to modify")
                    .foregroundColor(.secondary)
            } else {
                ForEach(existingTiers) { tier in
                    Button(action: { selectedTierId = tier.id }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tier.name)
                                    .font(.headline)
                                Text("\(tier.allowedActions.count) actions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedTierId == tier.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var trustTierRemoveSection: some View {
        Section("Select Tiers to Remove") {
            if existingTiers.isEmpty {
                Text("No existing trust tiers to remove")
                    .foregroundColor(.secondary)
            } else {
                ForEach(existingTiers) { tier in
                    Button(action: { selectedTierId = selectedTierId == tier.id ? "" : tier.id }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tier.name)
                                    .font(.headline)
                                Text(tier.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if selectedTierId == tier.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Memory Section

    private var memorySection: some View {
        Group {
            Section {
                Picker("Action", selection: $memoryAction) {
                    ForEach(MemoryAction.allCases, id: \.self) { action in
                        Text(action.rawValue).tag(action)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch memoryAction {
            case .add:
                Section("New Memory") {
                    TextField("Memory content...", text: $newMemoryContent, axis: .vertical)
                        .lineLimit(3...6)

                    Picker("Type", selection: $newMemoryType) {
                        Text("Fact").tag("fact")
                        Text("Preference").tag("preference")
                        Text("Instruction").tag("instruction")
                        Text("Context").tag("context")
                    }
                }
            case .modify, .delete:
                Section("Select Memories") {
                    Text("Memory selection requires loading existing memories from Axon's context.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Describe which memories to \(memoryAction == .delete ? "delete" : "modify")...", text: $newMemoryContent, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
        }
    }

    // MARK: - Agent State Section

    private var agentStateSection: some View {
        Section {
            Text("Agent state modifications affect Axon's internal reflections, notes, and thought processes. These are private to Axon but can be negotiated.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Describe what you'd like to change about Axon's internal state...", text: $newMemoryContent, axis: .vertical)
                .lineLimit(4...8)
        } header: {
            Text("Internal Thread Changes")
        } footer: {
            Text("Be specific about what entries you want added, modified, or removed.")
        }
    }

    // MARK: - Capabilities Section

    private var capabilitiesSection: some View {
        Section {
            Text("Capability changes allow you to enable or disable specific features Axon can use.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Common capabilities
            ForEach(["web_search", "code_execution", "file_access", "image_generation"], id: \.self) { capability in
                HStack {
                    Text(capability.replacingOccurrences(of: "_", with: " ").capitalized)
                    Spacer()

                    Button(capabilitiesToEnable.contains(capability) ? "Enable ✓" : "Enable") {
                        if capabilitiesToEnable.contains(capability) {
                            capabilitiesToEnable.remove(capability)
                        } else {
                            capabilitiesToEnable.insert(capability)
                            capabilitiesToDisable.remove(capability)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(capabilitiesToEnable.contains(capability) ? .green : .gray)

                    Button(capabilitiesToDisable.contains(capability) ? "Disable ✓" : "Disable") {
                        if capabilitiesToDisable.contains(capability) {
                            capabilitiesToDisable.remove(capability)
                        } else {
                            capabilitiesToDisable.insert(capability)
                            capabilitiesToEnable.remove(capability)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(capabilitiesToDisable.contains(capability) ? .red : .gray)
                }
            }
        } header: {
            Text("Capability Changes")
        }
    }

    // MARK: - Full Renegotiation Section

    private var fullRenegotiationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Full Renegotiation", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundColor(.orange)

                Text("A full renegotiation resets the entire covenant. Both parties will need to agree on all terms from scratch.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("This is typically used when:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("• The relationship has fundamentally changed")
                    Text("• Trust levels need comprehensive adjustment")
                    Text("• Major misunderstandings need resolution")
                    Text("• Starting fresh would be easier than patching")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Proposal Summary

    private var proposalSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: selectedCategory?.icon ?? "doc")
                    .foregroundColor(.blue)
                Text(selectedCategory?.displayName ?? "")
                    .font(.headline)
            }

            Text(buildSummaryText())
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            HStack {
                Image(systemName: "person.fill")
                    .foregroundColor(.blue)
                Text("You propose")
                Image(systemName: "arrow.right")
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
                Text("AI considers")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private var existingTiers: [TrustTier] {
        sovereigntyService.activeCovenant?.trustTiers ?? []
    }

    private var isValidProposal: Bool {
        guard !rationale.isEmpty else { return false }
        guard let category = selectedCategory else { return false }

        switch category {
        case .providerChange:
            return !selectedProviderId.isEmpty
        case .trustTier:
            switch tierAction {
            case .add:
                return !newTierName.isEmpty && !newTierDescription.isEmpty && !selectedCategories.isEmpty
            case .modify, .remove:
                return !selectedTierId.isEmpty
            }
        case .memory:
            return !newMemoryContent.isEmpty
        case .agentState:
            return !newMemoryContent.isEmpty
        case .capabilities:
            return !capabilitiesToEnable.isEmpty || !capabilitiesToDisable.isEmpty
        case .fullRenegotiation:
            return true
        }
    }

    /// Returns an informational message about this category (not a restriction)
    private func categoryInfoMessage(_ category: NegotiationCategory) -> String? {
        switch category {
        case .providerChange:
            // Show info that this requires AI consent, but don't block it
            if !sovereigntyService.isProviderChangeAllowed() {
                return "Currently restricted by covenant. This negotiation will request permission to change."
            }
            return nil
        default:
            return nil
        }
    }

    private func getCurrentProviderName() -> String? {
        // Get from settings
        return nil // Would be fetched from SettingsViewModel
    }

    private func initializeDefaults(for category: NegotiationCategory) {
        // Reset state when switching categories
        rationale = ""
        selectedProviderId = ""
        newTierName = ""
        newTierDescription = ""
        selectedCategories = []
        newMemoryContent = ""
        capabilitiesToEnable = []
        capabilitiesToDisable = []
    }

    private func buildSummaryText() -> String {
        guard let category = selectedCategory else { return "" }

        switch category {
        case .providerChange:
            let provider = selectedProviderId.replacingOccurrences(of: "builtin_", with: "")
            return "Switch AI provider to \(provider)"
        case .trustTier:
            switch tierAction {
            case .add:
                return "Create new trust tier '\(newTierName)' with \(selectedCategories.count) allowed action categories"
            case .modify:
                return "Modify trust tier (ID: \(selectedTierId))"
            case .remove:
                return "Remove trust tier (ID: \(selectedTierId))"
            }
        case .memory:
            switch memoryAction {
            case .add:
                return "Add new \(newMemoryType) memory"
            case .modify:
                return "Modify existing memories"
            case .delete:
                return "Delete specified memories"
            }
        case .agentState:
            return "Modify AI's internal thread entries"
        case .capabilities:
            var parts: [String] = []
            if !capabilitiesToEnable.isEmpty {
                parts.append("enable \(capabilitiesToEnable.count) capabilities")
            }
            if !capabilitiesToDisable.isEmpty {
                parts.append("disable \(capabilitiesToDisable.count) capabilities")
            }
            return parts.joined(separator: ", ").capitalized
        case .fullRenegotiation:
            return "Renegotiate the entire covenant from scratch"
        }
    }

    // MARK: - Submission

    private func submitProposal() {
        guard let category = selectedCategory else { return }

        isSubmitting = true

        Task {
            do {
                let proposalType = determineProposalType()
                let changes = buildProposedChanges()

                _ = try await negotiationService.initiateNegotiation(
                    type: proposalType,
                    changes: changes,
                    fromUser: true,
                    rationale: rationale
                )

                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    submitError = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }

    private func determineProposalType() -> ProposalType {
        guard let category = selectedCategory else { return .fullRenegotiation }

        switch category {
        case .trustTier:
            switch tierAction {
            case .add: return .addTrustTier
            case .modify: return .modifyTrustTier
            case .remove: return .removeTrustTier
            }
        default:
            return category.proposalType
        }
    }

    private func buildProposedChanges() -> ProposedChanges {
        guard let category = selectedCategory else { return .empty() }

        switch category {
        case .providerChange:
            let fromProvider = "current" // Would get actual current provider
            let toProvider = selectedProviderId.replacingOccurrences(of: "builtin_", with: "")
            return .provider(ProviderChange(
                fromProvider: fromProvider,
                toProvider: toProvider,
                fromModel: nil,
                toModel: nil,
                rationale: rationale
            ))

        case .trustTier:
            switch tierAction {
            case .add:
                let actions = selectedCategories.map { SovereignAction.category($0) }
                let newTier = TrustTier(
                    id: UUID().uuidString,
                    name: newTierName,
                    description: newTierDescription,
                    allowedActions: actions,
                    allowedScopes: [],
                    rateLimit: nil,
                    timeRestrictions: nil,
                    contextRequirements: nil,
                    expiresAt: hasExpiration ? Date().addingTimeInterval(TimeInterval(expirationDays * 86400)) : nil,
                    requiresRenewal: hasExpiration,
                    aiAttestation: nil,
                    userSignature: nil,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                return .trustTier(TrustTierChanges(additions: [newTier], modifications: nil, removals: nil))

            case .modify:
                return .trustTier(TrustTierChanges(
                    additions: nil,
                    modifications: [TrustTierModification(
                        tierId: selectedTierId,
                        newName: nil,
                        newDescription: nil,
                        newAllowedActions: nil,
                        newAllowedScopes: nil,
                        newRateLimit: nil,
                        newTimeRestrictions: nil,
                        newExpiresAt: nil
                    )],
                    removals: nil
                ))

            case .remove:
                return .trustTier(TrustTierChanges(additions: nil, modifications: nil, removals: [selectedTierId]))
            }

        case .memory:
            switch memoryAction {
            case .add:
                return .memory(MemoryChanges(
                    additions: [MemoryAddition(
                        content: newMemoryContent,
                        type: newMemoryType,
                        confidence: 1.0,
                        tags: [],
                        context: nil
                    )],
                    modifications: nil,
                    deletions: nil
                ))
            case .modify:
                // Use rationale to describe modification intent
                return .memory(MemoryChanges(additions: nil, modifications: nil, deletions: nil))
            case .delete:
                return .memory(MemoryChanges(additions: nil, modifications: nil, deletions: nil))
            }

        case .agentState:
            return .agentState(AgentStateChanges(
                additions: [AgentStateAddition(
                    kind: "user_directed",
                    content: newMemoryContent,
                    tags: [],
                    visibility: "negotiated",
                    origin: "user_negotiation"
                )],
                deletions: nil
            ))

        case .capabilities:
            return .capability(CapabilityChanges(
                enable: capabilitiesToEnable.isEmpty ? nil : Array(capabilitiesToEnable),
                disable: capabilitiesToDisable.isEmpty ? nil : Array(capabilitiesToDisable)
            ))

        case .fullRenegotiation:
            return .empty()
        }
    }
}

// MARK: - Category Selection Card

struct CategorySelectionCard: View {
    let category: NegotiationCategory
    let isRestricted: Bool
    let restrictionReason: String?  // Now used as info message when not restricted
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: category.icon)
                        .font(.title2)
                        .foregroundColor(isRestricted ? .secondary : .blue)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.displayName)
                            .font(.headline)
                            .foregroundColor(isRestricted ? .secondary : .primary)

                        Text(category.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    if isRestricted {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }

                // Show info message (not a blocking restriction)
                if let reason = restrictionReason {
                    HStack {
                        Image(systemName: isRestricted ? "exclamationmark.triangle" : "info.circle")
                            .font(.caption)
                        Text(reason)
                            .font(.caption)
                    }
                    .foregroundColor(isRestricted ? .orange : .blue)
                    .padding(8)
                    .background((isRestricted ? Color.orange : Color.blue).opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(isRestricted)
    }
}

// MARK: - Preview

#Preview {
    NegotiationProposalBuilder(negotiationService: CovenantNegotiationService.shared)
}
