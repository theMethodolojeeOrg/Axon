//
//  ToolInvocationSheet.swift
//  Axon
//
//  Sheet for directly invoking a tool via the /use command.
//  Allows users to input a query and execute a tool themselves.
//

import SwiftUI

// MARK: - Tool Invocation Sheet

struct ToolInvocationSheet: View {
    let tool: ToolSuggestion
    let onDismiss: () -> Void
    let onResult: (String, Bool) -> Void  // (result, success)

    @State private var query: String = ""
    @State private var urlField: String = ""  // For URL-based tools
    @State private var noteVisibility: NoteVisibility = .userOnly  // For Create Note
    @State private var executionState: ExecutionState = .idle
    @State private var resultText: String = ""
    @FocusState private var isQueryFocused: Bool
    @FocusState private var isUrlFocused: Bool

    /// Note visibility options for Create Note
    private enum NoteVisibility: String, CaseIterable {
        case userOnly = "Private"
        case mutual = "Shared with AI"

        var description: String {
            switch self {
            case .userOnly: return "Only you can see the contents. AI sees that a note exists."
            case .mutual: return "Both you and AI can read this note."
            }
        }

        var icon: String {
            switch self {
            case .userOnly: return "lock.fill"
            case .mutual: return "person.2.fill"
            }
        }
    }

    private enum ExecutionState {
        case idle
        case executing
        case success
        case failure
    }

    /// Check if this is a user-special tool (handled differently)
    private var isUserSpecialTool: Bool {
        tool.toolId.hasPrefix("user_")
    }

    /// Check if this is the Create Note tool (saves to Internal Thread)
    private var isCreateNoteTool: Bool {
        tool.toolId == "user_create_note"
    }

    /// Check if this tool needs a URL field
    private var needsUrlField: Bool {
        tool.toolId == "url_context"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Tool Header
                    toolHeader

                    Divider()
                        .background(AppColors.divider)

                    // Input Section (varies by tool type)
                    if isUserSpecialTool {
                        userSpecialInputSection
                    } else if needsUrlField {
                        urlInputSection
                    } else {
                        queryInputSection
                    }

                    // Result Section (if executed)
                    if executionState != .idle {
                        resultSection
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Action Buttons pinned to bottom
                actionButtons
            }
            .background(AppColors.substratePrimary)
            .navigationTitle(isUserSpecialTool ? "User Action" : "Run Tool")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            isQueryFocused = true
        }
    }

    // MARK: - Tool Header

    private var toolHeader: some View {
        HStack(spacing: 14) {
            // Tool Icon
            Image(systemName: tool.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.signalLichen)
                )

            // Tool Info
            VStack(alignment: .leading, spacing: 4) {
                Text(tool.displayName)
                    .font(AppTypography.bodyLarge(.semibold))
                    .foregroundColor(AppColors.textPrimary)

                Text(tool.description)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding()
        .background(AppColors.signalLichen.opacity(0.08))
    }

    // MARK: - Query Input

    private var queryInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Query")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)

            TextEditor(text: $query)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 100, maxHeight: 160)
                .background(AppColors.substrateTertiary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isQueryFocused ? AppColors.signalLichen : AppColors.glassBorder, lineWidth: 1)
                )
                .focused($isQueryFocused)

            // Hint text
            Text(queryHint)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
        }
        .padding()
    }

    private var queryHint: String {
        switch tool.toolId {
        case "google_search", "openai_web_search":
            return "e.g., \"current weather in San Francisco\""
        case "url_context":
            return "e.g., \"What are the main points?\""
        case "code_execution":
            return "e.g., \"Calculate fibonacci(20)\""
        case "google_maps":
            return "e.g., \"Coffee shops near Times Square\""
        case "conversation_search":
            return "e.g., \"What did we discuss about the project?\""
        case "create_memory":
            return "e.g., \"I prefer detailed explanations\""
        case "query_covenant":
            return "e.g., \"What are your current guidelines?\""
        case "query_system_state":
            return "e.g., \"What models are available?\""
        case "query_device_presence":
            return "e.g., \"What devices are connected?\""
        default:
            return "Enter your query for this tool"
        }
    }

    // MARK: - URL Input Section (for url_context)

    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // URL Field
            VStack(alignment: .leading, spacing: 8) {
                Text("URL")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)

                TextField("https://example.com/article", text: $urlField)
                    .font(.system(size: 15))
                    .textContentType(.URL)
                    #if !os(macOS)
                    .autocapitalization(.none)
                    #endif
                    .disableAutocorrection(true)
                    .padding(12)
                    .background(AppColors.substrateTertiary)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isUrlFocused ? AppColors.signalLichen : AppColors.glassBorder, lineWidth: 1)
                    )
                    .focused($isUrlFocused)
            }

            // Question/Query Field
            VStack(alignment: .leading, spacing: 8) {
                Text("What would you like to know?")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)

                TextEditor(text: $query)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 80, maxHeight: 120)
                    .background(AppColors.substrateTertiary)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isQueryFocused ? AppColors.signalLichen : AppColors.glassBorder, lineWidth: 1)
                    )
                    .focused($isQueryFocused)

                Text("e.g., \"Summarize this article\" or \"What are the main points?\"")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding()
    }

    // MARK: - User Special Input Section

    private var userSpecialInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch tool.toolId {
            case "user_create_note":
                createNoteInput
            case "user_propose_covenant":
                covenantProposalInput
            case "user_feedback":
                feedbackInput
            case "user_request_summary":
                summaryRequestInput
            default:
                queryInputSection
            }
        }
        .padding()
    }

    private var covenantProposalInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Propose a Change")
                .font(AppTypography.bodyMedium(.semibold))
                .foregroundColor(AppColors.textPrimary)

            Text("Describe what change you'd like to propose to Axon's guidelines or behavior.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)

            TextEditor(text: $query)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 120, maxHeight: 200)
                .background(AppColors.substrateTertiary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isQueryFocused ? AppColors.signalLichen : AppColors.glassBorder, lineWidth: 1)
                )
                .focused($isQueryFocused)

            Text("e.g., \"I'd like you to be more concise in your responses\" or \"Please ask clarifying questions before making assumptions\"")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
        }
    }

    private var feedbackInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Feedback")
                .font(AppTypography.bodyMedium(.semibold))
                .foregroundColor(AppColors.textPrimary)

            Text("Share feedback about AI responses, behavior, or suggestions for improvement.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)

            TextEditor(text: $query)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 120, maxHeight: 200)
                .background(AppColors.substrateTertiary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isQueryFocused ? AppColors.signalLichen : AppColors.glassBorder, lineWidth: 1)
                )
                .focused($isQueryFocused)

            Text("e.g., \"Your last response was too long\" or \"I appreciate the detailed explanations\"")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
        }
    }

    private var summaryRequestInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary Request")
                .font(AppTypography.bodyMedium(.semibold))
                .foregroundColor(AppColors.textPrimary)

            Text("What aspects of the conversation would you like summarized?")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)

            TextEditor(text: $query)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 80, maxHeight: 120)
                .background(AppColors.substrateTertiary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isQueryFocused ? AppColors.signalLichen : AppColors.glassBorder, lineWidth: 1)
                )
                .focused($isQueryFocused)

            Text("Leave blank for a general summary, or specify: \"key decisions\", \"action items\", etc.")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
        }
    }

    private var createNoteInput: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Create Note")
                .font(AppTypography.bodyMedium(.semibold))
                .foregroundColor(AppColors.textPrimary)

            Text("Save a note to your Internal Thread. Notes persist across conversations.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)

            // Note content
            TextEditor(text: $query)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 120, maxHeight: 200)
                .background(AppColors.substrateTertiary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isQueryFocused ? AppColors.signalLichen : AppColors.glassBorder, lineWidth: 1)
                )
                .focused($isQueryFocused)

            // Visibility picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Visibility")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)

                HStack(spacing: 12) {
                    ForEach(NoteVisibility.allCases, id: \.self) { visibility in
                        Button {
                            noteVisibility = visibility
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: visibility.icon)
                                    .font(.system(size: 12))
                                Text(visibility.rawValue)
                                    .font(AppTypography.bodySmall())
                            }
                            .foregroundColor(noteVisibility == visibility ? .white : AppColors.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(noteVisibility == visibility ? AppColors.signalLichen : AppColors.substrateTertiary)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(noteVisibility.description)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            // Mutual transparency hint
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                Text("Axon can see that a note exists, but must ask permission to read private notes.")
                    .font(AppTypography.labelSmall())
            }
            .foregroundColor(AppColors.textTertiary.opacity(0.8))
            .padding(.top, 4)
        }
    }

    // MARK: - Result Section

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // State indicator
                switch executionState {
                case .executing:
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Running...")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalMercury)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.signalLichen)
                    Text("Success")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalLichen)
                case .failure:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.signalHematite)
                    Text("Failed")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalHematite)
                case .idle:
                    EmptyView()
                }

                Spacer()

                // Copy button for result
                if !resultText.isEmpty {
                    Button {
                        #if os(iOS)
                        UIPasteboard.general.string = resultText
                        #else
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(resultText, forType: .string)
                        #endif
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Result text
            if !resultText.isEmpty {
                ScrollView {
                    Text(resultText)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(12)
                .background(AppColors.substrateTertiary)
                .cornerRadius(12)
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    // MARK: - Action Buttons

    /// Button text based on tool type
    private var actionButtonText: String {
        if executionState == .executing {
            return isCreateNoteTool ? "Saving..." : "Running..."
        }
        if isUserSpecialTool {
            switch tool.toolId {
            case "user_create_note":
                return "Save Note"
            case "user_propose_covenant":
                return "Send Proposal"
            case "user_feedback":
                return "Send Feedback"
            case "user_request_summary":
                return "Request Summary"
            default:
                return "Send"
            }
        }
        return "Run Tool"
    }

    /// Button icon based on tool type
    private var actionButtonIcon: String {
        if isCreateNoteTool {
            return "square.and.arrow.down.fill"
        }
        if isUserSpecialTool {
            return "paperplane.fill"
        }
        return "play.fill"
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Run/Send button
            Button {
                executeTool()
            } label: {
                HStack(spacing: 8) {
                    if executionState == .executing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: actionButtonIcon)
                            .font(.system(size: 14))
                    }
                    Text(actionButtonText)
                        .font(AppTypography.bodyMedium(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canExecute ? AppColors.signalLichen : AppColors.textDisabled)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canExecute)

            // Use Result button (only after success for non-user-special tools)
            if executionState == .success && !resultText.isEmpty && !isUserSpecialTool {
                Button {
                    onResult(resultText, true)
                    onDismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 14))
                        Text("Use Result")
                            .font(AppTypography.bodyMedium(.semibold))
                    }
                    .foregroundColor(AppColors.signalLichen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.signalLichen, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(AppColors.substrateSecondary)
    }

    private var canExecute: Bool {
        guard executionState != .executing else { return false }

        // User special tools just need some input (or none for summary)
        if isUserSpecialTool {
            if tool.toolId == "user_request_summary" {
                return true  // Can request summary without specific query
            }
            return !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        // URL tools need both URL and query
        if needsUrlField {
            return !urlField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        // Regular tools just need a query
        return !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Build the final query string based on tool type
    private var finalQuery: String {
        if needsUrlField {
            // Combine URL and query for url_context
            let trimmedUrl = urlField.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedQuery.isEmpty {
                return "Summarize \(trimmedUrl)"
            }
            return "\(trimmedQuery) \(trimmedUrl)"
        }
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tool Execution

    private func executeTool() {
        guard canExecute else { return }

        // Handle user-special tools differently - they send a message to AI
        if isUserSpecialTool {
            executeUserSpecialTool()
            return
        }

        executionState = .executing
        resultText = ""

        Task {
            do {
                let request = ToolRequest(tool: tool.toolId, query: finalQuery)

                // Get Gemini API key for tool execution
                let geminiKey = await MainActor.run {
                    SettingsViewModel.shared.getAPIKey(.gemini) ?? ""
                }

                let result = try await ToolProxyService.shared.executeToolRequest(
                    request,
                    geminiApiKey: geminiKey,
                    conversationContext: nil
                )

                await MainActor.run {
                    if result.success {
                        executionState = .success
                        resultText = result.result
                    } else {
                        executionState = .failure
                        resultText = result.result
                    }
                }
            } catch {
                await MainActor.run {
                    executionState = .failure
                    resultText = error.localizedDescription
                }
            }
        }
    }

    /// Handle user-special tools by formatting a message to send to AI
    private func executeUserSpecialTool() {
        // Create Note is handled separately - it saves to Internal Thread
        if isCreateNoteTool {
            executeCreateNote()
            return
        }

        let message: String
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        switch tool.toolId {
        case "user_propose_covenant":
            message = """
            **[User Covenant Proposal]**

            I'd like to propose the following change to our interaction guidelines:

            \(trimmedQuery)

            Please consider this proposal and let me know your thoughts. If you agree, we can discuss how to implement this change.
            """

        case "user_feedback":
            message = """
            **[User Feedback]**

            \(trimmedQuery)

            Please acknowledge this feedback and consider it for future interactions.
            """

        case "user_request_summary":
            if trimmedQuery.isEmpty {
                message = "Please provide a summary of our conversation so far, including the main topics we've discussed and any key decisions or conclusions."
            } else {
                message = "Please provide a summary of our conversation, focusing on: \(trimmedQuery)"
            }

        default:
            message = trimmedQuery
        }

        // Pass the formatted message back to be sent
        onResult(message, true)
        onDismiss()
    }

    /// Save a user note to the Internal Thread
    private func executeCreateNote() {
        let trimmedContent = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        executionState = .executing

        Task {
            do {
                // Determine visibility based on user selection
                let _ = noteVisibility // reserved for future: finer-grained visibility
                // Note: We use .aiOnly for "Private" because .aiOnly means Axon CAN'T see contents
                // But we need to invert the logic - if user wants it private FROM AI, we need a new approach
                // Actually looking at the model: .aiOnly means only AI can see, .userVisible means user can see
                // For "Private" we want user to see but AI to need permission
                // Let's use .userVisible for both, but we'll add a tag to indicate privacy

                _ = try await AgentStateService.shared.appendEntry(
                    kind: .note,
                    content: trimmedContent,
                    tags: noteVisibility == .userOnly ? ["user_private"] : [],
                    visibility: .userVisible,  // User can always see their own notes
                    origin: .user,
                    skipConsent: true  // User-created notes don't need AI consent
                )

                await MainActor.run {
                    executionState = .success
                    resultText = "Note saved to Internal Thread"

                    // Close after a brief moment to show success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        onResult("", true)  // No message to send, just close
                        onDismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    executionState = .failure
                    resultText = "Failed to save note: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ToolInvocationSheet(
        tool: ToolSuggestion(
            id: "google_search",
            toolId: "google_search",
            displayName: "Google Search",
            description: "Search the web for current information",
            icon: "magnifyingglass",
            category: "Gemini Tools"
        ),
        onDismiss: {},
        onResult: { _, _ in }
    )
}
