//
//  TrustTierManagementView.swift
//  Axon
//
//  Visualize and manage trust tiers - the negotiated contracts
//  between AI and user that define pre-approved action categories.
//

import SwiftUI

struct TrustTierManagementView: View {
    @ObservedObject var sovereigntyService = SovereigntyService.shared
    @ObservedObject var negotiationService = CovenantNegotiationService.shared

    @State private var showingNewTierSheet = false
    @State private var selectedTier: TrustTier?
    @State private var showingTierDetail = false

    var body: some View {
        List {
            // Active Tiers Section
            if !activeTiers.isEmpty {
                Section {
                    ForEach(activeTiers) { tier in
                        TrustTierCard(tier: tier)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTier = tier
                                showingTierDetail = true
                            }
                    }
                } header: {
                    Label("Active Trust Tiers", systemImage: "checkmark.shield.fill")
                }
            }

            // Expiring Soon Section
            if !expiringSoonTiers.isEmpty {
                Section {
                    ForEach(expiringSoonTiers) { tier in
                        TrustTierCard(tier: tier, showWarning: true)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTier = tier
                                showingTierDetail = true
                            }
                    }
                } header: {
                    Label("Expiring Soon", systemImage: "clock.badge.exclamationmark")
                        .foregroundColor(.orange)
                }
            }

            // Expired Tiers Section
            if !expiredTiers.isEmpty {
                Section {
                    ForEach(expiredTiers) { tier in
                        TrustTierCard(tier: tier, isExpired: true)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTier = tier
                                showingTierDetail = true
                            }
                    }
                } header: {
                    Label("Expired", systemImage: "clock.badge.xmark")
                        .foregroundColor(.secondary)
                }
            }

            // Empty State
            if activeTiers.isEmpty && expiringSoonTiers.isEmpty && expiredTiers.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Trust Tiers",
                        systemImage: "shield.slash",
                        description: Text("Trust tiers are negotiated contracts that pre-approve certain actions. Create one to streamline your workflow.")
                    )
                }
            }

            // Add New Tier Section
            Section {
                Button(action: { showingNewTierSheet = true }) {
                    Label("Propose New Trust Tier", systemImage: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
            } footer: {
                Text("New trust tiers require negotiation and consent from both you and the AI.")
                    .font(.caption)
            }
        }
        .navigationTitle("Trust Tiers")
        .sheet(isPresented: $showingNewTierSheet) {
            NewTrustTierSheet(negotiationService: negotiationService)
                #if os(macOS)
                .frame(minWidth: 480, idealWidth: 550, minHeight: 550, idealHeight: 700)
                #endif
        }
        .sheet(isPresented: $showingTierDetail) {
            if let tier = selectedTier {
                TrustTierDetailSheet(tier: tier, negotiationService: negotiationService)
                    #if os(macOS)
                    .frame(minWidth: 500, idealWidth: 600, minHeight: 550, idealHeight: 750)
                    #endif
            }
        }
    }

    // MARK: - Computed Properties

    private var allTiers: [TrustTier] {
        sovereigntyService.activeCovenant?.trustTiers ?? []
    }

    private var activeTiers: [TrustTier] {
        allTiers.filter { !$0.isExpired && !$0.isExpiringSoon }
    }

    private var expiringSoonTiers: [TrustTier] {
        allTiers.filter { $0.isExpiringSoon && !$0.isExpired }
    }

    private var expiredTiers: [TrustTier] {
        allTiers.filter { $0.isExpired }
    }
}

// MARK: - Trust Tier Card

struct TrustTierCard: View {
    let tier: TrustTier
    var showWarning: Bool = false
    var isExpired: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: tierIcon)
                    .foregroundColor(tierColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.name)
                        .font(.headline)
                        .foregroundColor(isExpired ? .secondary : .primary)

                    Text(tier.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if showWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }

                if isExpired {
                    Text("Expired")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
            }

            // Allowed Actions Preview
            HStack(spacing: 4) {
                ForEach(Array(tier.allowedActions.prefix(3).enumerated()), id: \.offset) { _, action in
                    ActionCategoryBadge(category: action.category, compact: true)
                }

                if tier.allowedActions.count > 3 {
                    Text("+\(tier.allowedActions.count - 3)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }

            // Signatures and Expiration
            HStack {
                // Dual signature indicator
                if tier.isFullySigned {
                    HStack(spacing: 4) {
                        Image(systemName: "signature")
                            .font(.caption2)
                        Text("Both signed")
                            .font(.caption2)
                    }
                    .foregroundColor(.green)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "signature")
                            .font(.caption2)
                        Text("Pending signatures")
                            .font(.caption2)
                    }
                    .foregroundColor(.orange)
                }

                Spacer()

                // Expiration
                if let expiresAt = tier.expiresAt {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(expiresAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                    }
                    .foregroundColor(isExpired ? .red : (showWarning ? .orange : .secondary))
                } else {
                    Text("No expiration")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(isExpired ? Color.secondary.opacity(0.05) : Color.blue.opacity(0.05))
        .cornerRadius(12)
        .opacity(isExpired ? 0.7 : 1.0)
    }

    private var tierIcon: String {
        let categories = tier.allowedActions.map { $0.category }
        if categories.contains(where: { $0.affectsWorld }) {
            return "arrow.right.circle.fill"
        } else {
            return "arrow.left.circle.fill"
        }
    }

    private var tierColor: Color {
        if isExpired { return .secondary }
        if showWarning { return .orange }
        return .blue
    }
}

// MARK: - Action Category Badge

struct ActionCategoryBadge: View {
    let category: ActionCategory
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.tierIcon)
                .font(compact ? .caption2 : .caption)

            if !compact {
                Text(category.displayName)
                    .font(.caption)
            }
        }
        .foregroundColor(categoryColor)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(categoryColor.opacity(0.1))
        .cornerRadius(compact ? 4 : 6)
    }

    private var categoryColor: Color {
        category.affectsWorld ? .blue : .purple
    }
}

// MARK: - Trust Tier Detail Sheet

struct TrustTierDetailSheet: View {
    let tier: TrustTier
    @ObservedObject var negotiationService: CovenantNegotiationService
    @Environment(\.dismiss) private var dismiss

    @State private var showingModifySheet = false
    @State private var showingRevokeConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                // Overview Section
                Section("Overview") {
                    LabeledContent("Name", value: tier.name)

                    VStack(alignment: .leading) {
                        Text("Description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(tier.description)
                    }

                    if let expiresAt = tier.expiresAt {
                        LabeledContent("Expires") {
                            Text(expiresAt.formatted(date: .long, time: .shortened))
                                .foregroundColor(tier.isExpired ? .red : (tier.isExpiringSoon ? .orange : .secondary))
                        }
                    } else {
                        LabeledContent("Expires", value: "Never")
                    }

                    LabeledContent("Created", value: tier.createdAt.formatted(date: .abbreviated, time: .shortened))
                }

                // Allowed Actions Section
                Section("Allowed Actions") {
                    ForEach(Array(tier.allowedActions.enumerated()), id: \.offset) { _, action in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                ActionCategoryBadge(category: action.category)

                                Spacer()

                                if action.category.affectsWorld {
                                    Text("AI -> World")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                } else {
                                    Text("User -> AI")
                                        .font(.caption2)
                                        .foregroundColor(.purple)
                                }
                            }

                            if let specificAction = action.specificAction {
                                Text("Specific: \(specificAction)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Scopes Section
                if !tier.allowedScopes.isEmpty {
                    Section("Scopes") {
                        ForEach(Array(tier.allowedScopes.enumerated()), id: \.offset) { _, scope in
                            ScopeDetailRow(scope: scope)
                        }
                    }
                }

                // Constraints Section
                Section("Constraints") {
                    if let rateLimit = tier.rateLimit {
                        LabeledContent("Rate Limit") {
                            Text("\(rateLimit.maxCalls) per \(rateLimit.windowSeconds / 60) min")
                        }
                    } else {
                        LabeledContent("Rate Limit", value: "None")
                    }

                    if let timeRestrictions = tier.timeRestrictions {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Time Restrictions")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("\(timeRestrictions.allowedHoursStart):00 - \(timeRestrictions.allowedHoursEnd):00")
                                .font(.caption)
                        }
                    }

                    LabeledContent("Requires Renewal", value: tier.requiresRenewal ? "Yes" : "No")
                }

                // Signatures Section
                Section("Signatures") {
                    // AI Attestation
                    if let attestation = tier.aiAttestation {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "brain.head.profile")
                                    .foregroundColor(.purple)
                                Text("AI Attestation")
                                    .font(.headline)
                            }

                            Text(attestation.reasoning.summary)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack {
                                Text("Signature: \(attestation.shortSignature)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text(attestation.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("AI attestation pending")
                            .foregroundColor(.secondary)
                    }

                    // User Signature
                    if let signature = tier.userSignature {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.blue)
                                Text("User Signature")
                                    .font(.headline)
                            }

                            HStack {
                                Image(systemName: signature.biometricSystemImage)
                                    .font(.caption)
                                Text(signature.biometricDisplayName)
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)

                            HStack {
                                Text("Signature: \(signature.shortSignature)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text(signature.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("User signature pending")
                            .foregroundColor(.secondary)
                    }
                }

                // Actions Section
                Section {
                    if tier.isExpired {
                        Button(action: { initiateRenewal() }) {
                            Label("Renew Trust Tier", systemImage: "arrow.clockwise")
                        }
                    } else {
                        Button(action: { showingModifySheet = true }) {
                            Label("Propose Modification", systemImage: "pencil")
                        }
                    }

                    Button(role: .destructive, action: { showingRevokeConfirmation = true }) {
                        Label("Revoke Trust Tier", systemImage: "xmark.shield")
                    }
                } footer: {
                    Text("Modifications and revocations require re-negotiation with both parties.")
                        .font(.caption)
                }
            }
            .navigationTitle("Trust Tier Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingModifySheet) {
                ModifyTrustTierSheet(tier: tier, negotiationService: negotiationService)
                    #if os(macOS)
                    .frame(minWidth: 450, idealWidth: 520, minHeight: 400, idealHeight: 500)
                    #endif
            }
            .confirmationDialog(
                "Revoke Trust Tier?",
                isPresented: $showingRevokeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Revoke", role: .destructive) {
                    initiateRevocation()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will require re-negotiation. The AI must consent to removing this trust tier.")
            }
        }
    }

    private func initiateRenewal() {
        Task {
            _ = try? await negotiationService.initiateNegotiation(
                type: .modifyTrustTier,
                changes: .trustTier(TrustTierChanges(
                    additions: nil,
                    modifications: [TrustTierModification(
                        tierId: tier.id,
                        newName: nil,
                        newDescription: nil,
                        newAllowedActions: nil,
                        newAllowedScopes: nil,
                        newRateLimit: nil,
                        newTimeRestrictions: nil,
                        newExpiresAt: Date().addingTimeInterval(30 * 24 * 60 * 60)
                    )],
                    removals: nil
                )),
                fromUser: true,
                rationale: "Renewing expired trust tier: \(tier.name)"
            )
            dismiss()
        }
    }

    private func initiateRevocation() {
        Task {
            _ = try? await negotiationService.initiateNegotiation(
                type: .removeTrustTier,
                changes: .trustTier(TrustTierChanges(
                    additions: nil,
                    modifications: nil,
                    removals: [tier.id]
                )),
                fromUser: true,
                rationale: "Revoking trust tier: \(tier.name)"
            )
            dismiss()
        }
    }
}

// MARK: - Scope Detail Row

struct ScopeDetailRow: View {
    let scope: ActionScope

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: scopeIcon)
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(scope.scopeType.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(scope.pattern)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if scope.includeSubpaths {
                    Text("Includes subpaths")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
    }

    private var scopeIcon: String {
        switch scope.scopeType {
        case .filePath: return "folder"
        case .urlDomain: return "globe"
        case .toolId: return "wrench"
        case .memoryType: return "brain"
        case .memoryTag: return "tag"
        }
    }
}

// MARK: - New Trust Tier Sheet

struct NewTrustTierSheet: View {
    @ObservedObject var negotiationService: CovenantNegotiationService
    @Environment(\.dismiss) private var dismiss

    @State private var tierName = ""
    @State private var tierDescription = ""
    @State private var selectedCategories: Set<ActionCategory> = []
    @State private var expirationDays: Int = 30
    @State private var hasExpiration = true
    @State private var rationale = ""

    // Scope configuration
    @State private var allowedPaths: [String] = []
    @State private var newPath = ""

    // Negotiation state
    @State private var isNegotiating = false
    @State private var negotiationPhase: NegotiationPhase = .input
    @State private var aiReasoning: String = ""
    @State private var errorMessage: String?

    enum NegotiationPhase {
        case input
        case awaitingAI
        case aiConsented
        case finalizing
        case completed
        case failed
    }

    var body: some View {
        NavigationStack {
            Group {
                switch negotiationPhase {
                case .input:
                    inputForm
                case .awaitingAI:
                    awaitingAIView
                case .aiConsented:
                    aiConsentedView
                case .finalizing:
                    finalizingView
                case .completed:
                    completedView
                case .failed:
                    failedView
                }
            }
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if negotiationPhase != .completed {
                        Button("Cancel") {
                            if negotiationPhase != .input {
                                negotiationService.cancelNegotiation()
                            }
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if negotiationPhase == .input {
                        Button("Propose") {
                            proposeNewTier()
                        }
                        .disabled(!isValid)
                    } else if negotiationPhase == .completed {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch negotiationPhase {
        case .input: return "New Trust Tier"
        case .awaitingAI: return "Awaiting AI Response"
        case .aiConsented: return "AI Consented"
        case .finalizing: return "Finalizing"
        case .completed: return "Trust Tier Created"
        case .failed: return "Negotiation Failed"
        }
    }

    // MARK: - Input Form

    private var inputForm: some View {
        Form {
            // Basic Info
            Section("Trust Tier Details") {
                #if os(macOS)
                LabeledContent("Name") {
                    TextField("", text: $tierName)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Description") {
                    TextField("", text: $tierDescription, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
                #else
                TextField("Name", text: $tierName)
                TextField("Description", text: $tierDescription, axis: .vertical)
                    .lineLimit(2...4)
                #endif
            }

            // Action Categories
            Section {
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
                            #if os(macOS)
                            Text(category.affectsWorld ? "AI → World" : "User → AI")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(minWidth: 80, alignment: .trailing)
                            #else
                            Text(category.affectsWorld ? "AI -> World" : "User -> AI")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            #endif
                        }
                    }
                }
            } header: {
                Text("Allowed Actions")
            } footer: {
                Text("AI → World actions require your biometric. User → AI actions require AI consent.")
            }

            // Scope Configuration
            Section("Scope (Optional)") {
                // Allowed paths
                ForEach(allowedPaths, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder")
                        Text(path)
                            .font(.caption)
                        Spacer()
                        Button(action: { allowedPaths.removeAll { $0 == path } }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    #if os(macOS)
                    TextField("Add path (e.g., ~/Projects)", text: $newPath)
                        .textFieldStyle(.roundedBorder)
                    #else
                    TextField("Add path (e.g., ~/Projects)", text: $newPath)
                        .font(.caption)
                    #endif

                    Button(action: {
                        if !newPath.isEmpty {
                            allowedPaths.append(newPath)
                            newPath = ""
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newPath.isEmpty)
                }
            }

            // Expiration
            Section("Expiration") {
                Toggle("Set Expiration", isOn: $hasExpiration)

                if hasExpiration {
                    #if os(macOS)
                    LabeledContent("Duration") {
                        Stepper("\(expirationDays) days", value: $expirationDays, in: 1...365)
                    }
                    #else
                    Stepper("Expires in \(expirationDays) days", value: $expirationDays, in: 1...365)
                    #endif
                }
            }

            // Rationale
            Section {
                #if os(macOS)
                TextField("Why do you want this trust tier?", text: $rationale, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                #else
                TextField("Why do you want this trust tier?", text: $rationale, axis: .vertical)
                    .lineLimit(3...6)
                #endif
            } header: {
                Text("Your Rationale")
            } footer: {
                Text("The AI will consider your reasoning when deciding whether to consent.")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    // MARK: - Awaiting AI View

    private var awaitingAIView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Requesting AI Consent...")
                .font(.headline)

            Text("The AI is reviewing your trust tier proposal and will provide its reasoning.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    // MARK: - AI Consented View

    private var aiConsentedView: some View {
        VStack(spacing: 20) {
            // Success indicator
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("AI Consented")
                .font(.title2)
                .fontWeight(.semibold)

            // AI Reasoning
            VStack(alignment: .leading, spacing: 12) {
                Label("AI Reasoning", systemImage: "brain.head.profile")
                    .font(.headline)

                Text(aiReasoning)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding()

            // Finalize button
            Button(action: finalizeWithBiometric) {
                HStack {
                    Image(systemName: "faceid")
                    Text("Confirm with Biometric")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding(.horizontal)

            Text("Your biometric signature is required to finalize this trust tier.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    // MARK: - Finalizing View

    private var finalizingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Finalizing Trust Tier...")
                .font(.headline)

            Text("Applying your signature and creating the trust tier.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Completed View

    private var completedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("Trust Tier Created!")
                .font(.title)
                .fontWeight(.bold)

            Text("'\(tierName)' is now active and both parties have signed.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    // MARK: - Failed View

    private var failedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("Negotiation Failed")
                .font(.title2)
                .fontWeight(.semibold)

            if let error = errorMessage {
                Text(error)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Try Again") {
                negotiationPhase = .input
                errorMessage = nil
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    // MARK: - Validation

    private var isValid: Bool {
        !tierName.isEmpty && !tierDescription.isEmpty && !selectedCategories.isEmpty && !rationale.isEmpty
    }

    // MARK: - Actions

    private func proposeNewTier() {
        let actions = selectedCategories.map { category in
            SovereignAction.category(category)
        }

        let scopes = allowedPaths.map { path in
            ActionScope.filePath(path, includeSubpaths: true)
        }

        let newTier = TrustTier(
            id: UUID().uuidString,
            name: tierName,
            description: tierDescription,
            allowedActions: actions,
            allowedScopes: scopes,
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

        negotiationPhase = .awaitingAI

        Task {
            do {
                let proposal = try await negotiationService.initiateNegotiation(
                    type: .addTrustTier,
                    changes: .trustTier(TrustTierChanges(
                        additions: [newTier],
                        modifications: nil,
                        removals: nil
                    )),
                    fromUser: true,
                    rationale: rationale
                )

                // Check if AI consented
                if let aiResponse = proposal.aiResponse, aiResponse.didConsent {
                    aiReasoning = aiResponse.reasoning.summary
                    negotiationPhase = .aiConsented
                } else if let aiResponse = proposal.aiResponse {
                    // AI declined
                    errorMessage = aiResponse.reasoning.summary
                    negotiationPhase = .failed
                } else {
                    // No AI response yet - check negotiation state
                    await checkNegotiationState()
                }
            } catch {
                errorMessage = error.localizedDescription
                negotiationPhase = .failed
            }
        }
    }

    private func checkNegotiationState() async {
        // Wait a moment for the negotiation to complete
        try? await Task.sleep(nanoseconds: 500_000_000)

        if let proposal = negotiationService.activeNegotiation {
            if let aiResponse = proposal.aiResponse, aiResponse.didConsent {
                aiReasoning = aiResponse.reasoning.summary
                negotiationPhase = .aiConsented
            } else if let aiResponse = proposal.aiResponse {
                errorMessage = aiResponse.reasoning.summary
                negotiationPhase = .failed
            } else {
                // Still waiting - check state
                switch negotiationService.negotiationState {
                case .finalizing:
                    aiReasoning = "AI has consented to this trust tier."
                    negotiationPhase = .aiConsented
                case .deadlocked:
                    errorMessage = "The negotiation reached a deadlock."
                    negotiationPhase = .failed
                default:
                    // Keep waiting or show generic consent
                    aiReasoning = "AI has reviewed and consented to this trust tier proposal."
                    negotiationPhase = .aiConsented
                }
            }
        }
    }

    private func finalizeWithBiometric() {
        negotiationPhase = .finalizing

        Task {
            do {
                _ = try await negotiationService.finalizeWithUserSignature()
                negotiationPhase = .completed
            } catch {
                errorMessage = error.localizedDescription
                negotiationPhase = .failed
            }
        }
    }
}

// MARK: - Modify Trust Tier Sheet

struct ModifyTrustTierSheet: View {
    let tier: TrustTier
    @ObservedObject var negotiationService: CovenantNegotiationService
    @Environment(\.dismiss) private var dismiss

    @State private var rationale = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Tier") {
                    LabeledContent("Name", value: tier.name)
                    LabeledContent("Actions", value: "\(tier.allowedActions.count)")
                    if let expiresAt = tier.expiresAt {
                        LabeledContent("Expires", value: expiresAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }

                Section("Proposed Changes") {
                    TextField("Describe your proposed changes...", text: $rationale, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section {
                    Text("Modifications require AI consent. The AI will review your proposal and may accept, decline, or suggest alternatives.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Modify Trust Tier")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Propose") {
                        proposeModification()
                    }
                    .disabled(rationale.isEmpty)
                }
            }
        }
    }

    private func proposeModification() {
        Task {
            _ = try? await negotiationService.initiateNegotiation(
                type: .modifyTrustTier,
                changes: .trustTier(TrustTierChanges(
                    additions: nil,
                    modifications: [TrustTierModification(
                        tierId: tier.id,
                        newName: nil,
                        newDescription: nil,
                        newAllowedActions: nil,
                        newAllowedScopes: nil,
                        newRateLimit: nil,
                        newTimeRestrictions: nil,
                        newExpiresAt: nil
                    )],
                    removals: nil
                )),
                fromUser: true,
                rationale: rationale
            )
            dismiss()
        }
    }
}

// MARK: - Extensions

extension TrustTier {
    var isExpiringSoon: Bool {
        guard let expiresAt = expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 7 * 24 * 60 * 60 && expiresAt.timeIntervalSinceNow > 0
    }
}

// Note: AIAttestation.shortSignature is defined in the model

// MARK: - Preview

#Preview {
    NavigationStack {
        TrustTierManagementView()
    }
}
