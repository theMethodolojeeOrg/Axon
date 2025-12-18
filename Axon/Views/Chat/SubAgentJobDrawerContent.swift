//
//  SubAgentJobDrawerContent.swift
//  Axon
//
//  Expanded drawer showing sub-agent job details.
//  Supports pretty and raw view modes with silo summary and attestation info.
//

import SwiftUI

// MARK: - Sub-Agent Job Drawer Content

/// Expanded drawer showing job details, silo summary, and attestations.
struct SubAgentJobDrawerContent: View {
    let job: SubAgentJob
    @State private var showRaw: Bool = false
    @EnvironmentObject private var orchestratorService: AgentOrchestratorService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Format toggle and copy button
            HStack {
                Picker("Format", selection: $showRaw) {
                    Text("Pretty").tag(false)
                    Text("Raw").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Spacer()

                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                        Text("Copy")
                            .font(AppTypography.labelSmall())
                    }
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Task section
            DrawerSection(title: "Task", icon: "doc.text") {
                Text(job.task)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .textSelection(.enabled)
            }

            // Context tags
            if !job.contextInjectionTags.isEmpty {
                DrawerSection(title: "Context Tags", icon: "tag") {
                    FlowLayout(spacing: 4) {
                        ForEach(job.contextInjectionTags, id: \.self) { tag in
                            Text("#\(tag.replacingOccurrences(of: "#", with: ""))")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.signalMercury)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.signalMercury.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }

            // Permissions summary
            DrawerSection(title: "Permissions", icon: "lock.shield") {
                HStack(spacing: 12) {
                    PermissionBadge(
                        label: "Read",
                        allowed: job.permissions.canRead
                    )
                    PermissionBadge(
                        label: "Write",
                        allowed: job.permissions.canWrite
                    )
                    Text("\(job.permissions.allowedTools.count) tools")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
            }

            // Model info
            if let provider = job.executedProvider ?? job.provider,
               let model = job.executedModel ?? job.model {
                DrawerSection(title: "Model", icon: "cpu") {
                    HStack {
                        Text(provider.displayName)
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.textPrimary)
                        Text("•")
                            .foregroundColor(AppColors.textTertiary)
                        Text(model)
                            .font(AppTypography.codeSmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }

            // Result section (if completed)
            if let result = job.result {
                DrawerSection(
                    title: result.success ? "Result" : "Error",
                    icon: result.success ? "checkmark.circle" : "exclamationmark.circle",
                    titleColor: result.success ? AppColors.textPrimary : AppColors.signalHematite
                ) {
                    if showRaw {
                        RawResultView(result: result)
                    } else {
                        PrettyResultView(result: result)
                    }
                }
            }

            // Silo summary (if available)
            if let siloId = job.siloId,
               let silo = orchestratorService.silos[siloId] {
                SiloSummarySection(silo: silo)
            }

            // Spawn recommendations (if any)
            if let recommendations = job.result?.spawnRecommendations, !recommendations.isEmpty {
                SpawnRecommendationsSection(recommendations: recommendations)
            }

            // Attestation chain
            AttestationSection(job: job)

            // Metadata footer
            MetadataFooter(job: job)
        }
        .padding(12)
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }

    // MARK: - Copy to Clipboard

    private func copyToClipboard() {
        var text = """
        Sub-Agent Job: \(job.role.displayName)
        ID: \(job.id)
        State: \(job.state.displayName)
        Task: \(job.task)
        Context Tags: \(job.contextInjectionTags.joined(separator: ", "))
        Permissions: \(job.permissions.permissionSummary)
        """

        if let result = job.result {
            text += """

            --- Result ---
            Success: \(result.success)
            Summary: \(result.summary)
            Full Response: \(result.fullResponse)
            """
            if let error = result.errorMessage {
                text += "\nError: \(error)"
            }
        }

        if let attestation = job.approvalAttestation {
            text += """

            --- Approval Attestation ---
            ID: \(attestation.id)
            Reasoning: \(attestation.reasoning)
            Model: \(attestation.modelId)
            """
        }

        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Drawer Section

private struct DrawerSection<Content: View>: View {
    let title: String
    let icon: String
    var titleColor: Color = AppColors.textPrimary
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(AppTypography.labelSmall(.medium))
            }
            .foregroundColor(titleColor)

            content
        }
    }
}

// MARK: - Permission Badge

private struct PermissionBadge: View {
    let label: String
    let allowed: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: allowed ? "checkmark" : "xmark")
                .font(.system(size: 8))
            Text(label)
                .font(AppTypography.labelSmall())
        }
        .foregroundColor(allowed ? AppColors.signalLichen : AppColors.signalHematite)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((allowed ? AppColors.signalLichen : AppColors.signalHematite).opacity(0.1))
        .cornerRadius(4)
    }
}

// MARK: - Pretty Result View

private struct PrettyResultView: View {
    let result: SubAgentJobResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.summary)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(5)

            if let questions = result.clarificationQuestions, !questions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Questions:")
                        .font(AppTypography.labelSmall(.medium))
                        .foregroundColor(AppColors.signalMercury)

                    ForEach(questions, id: \.self) { question in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                            Text(question)
                                .font(AppTypography.bodySmall())
                        }
                        .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(8)
                .background(AppColors.signalMercury.opacity(0.1))
                .cornerRadius(6)
            }

            if let error = result.errorMessage {
                Text(error)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.signalHematite)
            }
        }
    }
}

// MARK: - Raw Result View

private struct RawResultView: View {
    let result: SubAgentJobResult

    var body: some View {
        ScrollView {
            Text(result.fullResponse)
                .font(AppTypography.codeSmall())
                .foregroundColor(AppColors.textSecondary)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 200)
        .padding(8)
        .background(AppColors.substratePrimary)
        .cornerRadius(6)
    }
}

// MARK: - Silo Summary Section

private struct SiloSummarySection: View {
    let silo: SubAgentMemorySilo

    var body: some View {
        let summary = silo.summary()

        DrawerSection(title: "Silo Summary", icon: "archivebox") {
            VStack(alignment: .leading, spacing: 6) {
                // Entry counts
                HStack(spacing: 12) {
                    SiloCountBadge(icon: "eye", count: summary.observationCount, label: "obs")
                    SiloCountBadge(icon: "lightbulb", count: summary.inferenceCount, label: "inf")
                    SiloCountBadge(icon: "doc.text", count: summary.artifactCount, label: "art")
                }

                // Attention items
                if summary.needsAttention {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(summary.attentionItems, id: \.self) { item in
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 10))
                                Text(item)
                                    .font(AppTypography.labelSmall())
                            }
                            .foregroundColor(AppColors.signalMercury)
                        }
                    }
                }

                // Sealed status
                HStack {
                    Image(systemName: silo.isSealed ? "lock.fill" : "lock.open")
                        .font(.system(size: 10))
                    Text(silo.isSealed ? "Sealed" : "Open")
                        .font(AppTypography.labelSmall())

                    if silo.isCompactedLesson {
                        Text("• Compacted lesson")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.signalLichen)
                    } else if let expiresAt = silo.expiresAt {
                        Text("• Expires \(expiresAt.formatted(.relative(presentation: .named)))")
                            .font(AppTypography.labelSmall())
                    }
                }
                .foregroundColor(AppColors.textTertiary)
            }
        }
    }
}

// MARK: - Silo Count Badge

private struct SiloCountBadge: View {
    let icon: String
    let count: Int
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text("\(count)")
                .font(AppTypography.labelSmall(.medium))
            Text(label)
                .font(AppTypography.labelSmall())
        }
        .foregroundColor(count > 0 ? AppColors.textSecondary : AppColors.textTertiary)
    }
}

// MARK: - Spawn Recommendations Section

private struct SpawnRecommendationsSection: View {
    let recommendations: [SpawnRecommendation]

    var body: some View {
        DrawerSection(title: "Spawn Recommendations", icon: "arrow.triangle.branch") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(recommendations) { rec in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: rec.role.icon)
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.signalMercury)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(rec.role.displayName)
                                    .font(AppTypography.labelSmall(.medium))
                                PriorityBadge(priority: rec.priority)
                            }
                            Text(rec.task)
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(8)
                    .background(AppColors.substratePrimary)
                    .cornerRadius(6)
                }
            }
        }
    }
}

// MARK: - Priority Badge

private struct PriorityBadge: View {
    let priority: SpawnRecommendation.Priority

    var color: Color {
        switch priority {
        case .low: return AppColors.textTertiary
        case .medium: return AppColors.signalMercury
        case .high: return AppColors.signalHematite.opacity(0.7)
        case .critical: return AppColors.signalHematite
        }
    }

    var body: some View {
        Text(priority.rawValue.uppercased())
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.1))
            .cornerRadius(2)
    }
}

// MARK: - Attestation Section

private struct AttestationSection: View {
    let job: SubAgentJob

    var body: some View {
        let attestations = [
            ("Approval", job.approvalAttestation),
            ("Completion", job.completionAttestation),
            ("Termination", job.terminationAttestation)
        ].compactMap { name, att -> (String, JobAttestation)? in
            guard let att = att else { return nil }
            return (name, att)
        }

        if !attestations.isEmpty {
            DrawerSection(title: "Attestations", icon: "signature") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(attestations, id: \.0) { name, attestation in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: attestation.type.icon)
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.signalLichen)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(name)
                                        .font(AppTypography.labelSmall(.medium))
                                    Text("•")
                                        .foregroundColor(AppColors.textTertiary)
                                    Text(attestation.timestamp.formatted(.dateTime.hour().minute().second()))
                                        .font(AppTypography.codeSmall())
                                        .foregroundColor(AppColors.textTertiary)
                                }
                                Text(attestation.reasoning.prefix(100).description)
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Metadata Footer

private struct MetadataFooter: View {
    let job: SubAgentJob

    var body: some View {
        HStack {
            // Duration
            if let duration = job.duration {
                Label(formatDuration(duration), systemImage: "clock")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            // Cost
            if let cost = job.estimatedCostUSD {
                Label(String(format: "$%.4f", cost), systemImage: "dollarsign.circle")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            // Tokens
            if let usage = job.tokenUsage {
                Label("\(usage.totalTokens) tok", systemImage: "text.word.spacing")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            Spacer()

            // Job ID
            Text(job.id.prefix(8))
                .font(AppTypography.codeSmall())
                .foregroundColor(AppColors.textTertiary.opacity(0.5))
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int(duration * 1000))ms"
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, row) in result.rows.enumerated() {
            for item in row {
                let x = bounds.minX + item.x
                let y = bounds.minY + result.yOffsets[index]
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            }
        }
    }

    struct FlowResult {
        var rows: [[Item]] = []
        var yOffsets: [CGFloat] = []
        var size: CGSize = .zero

        struct Item {
            var index: Int
            var x: CGFloat
            var size: CGSize
        }

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentRow: [Item] = []
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0

            for (index, subview) in subviews.enumerated() {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && !currentRow.isEmpty {
                    rows.append(currentRow)
                    yOffsets.append(y)
                    y += maxHeight + spacing
                    currentRow = []
                    x = 0
                    maxHeight = 0
                }

                currentRow.append(Item(index: index, x: x, size: size))
                x += size.width + spacing
                maxHeight = max(maxHeight, size.height)
            }

            if !currentRow.isEmpty {
                rows.append(currentRow)
                yOffsets.append(y)
            }

            size = CGSize(width: maxWidth, height: y + maxHeight)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        SubAgentJobDrawerContent(job: {
            var job = SubAgentJob(
                role: .scout,
                task: "Explore the axon-bridge-vscode directory looking for network error handling patterns",
                contextInjectionTags: ["#VSIX", "#NetworkPatterns", "#ErrorHandling"]
            )
            job = job.started()
            job = job.finished()
            job = job.transitioning(to: .completed)
            job = job.withResult(SubAgentJobResult(
                summary: "Found 3 areas with network error handling in the WebSocket connection manager",
                fullResponse: "Full analysis of the codebase...",
                clarificationQuestions: nil,
                success: true,
                spawnRecommendations: [
                    SpawnRecommendation(
                        role: .mechanic,
                        task: "Fix the retry logic in WebSocketManager.swift",
                        contextTags: ["#VSIX"],
                        rationale: "The retry logic doesn't handle edge cases",
                        priority: .high
                    )
                ]
            ))
            return job
        }())
        .environmentObject(AgentOrchestratorService.shared)
        .padding()
    }
    .background(AppColors.substratePrimary)
}
