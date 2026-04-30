//
//  GroundingSourcesView.swift
//  Axon
//
//  Display grounding sources from tool responses (search results, maps, etc.)
//

import SwiftUI

// MARK: - Message Grounding Sources View (for use in chat bubbles)

struct MessageSourcesView: View {
    let sources: [MessageGroundingSource]
    @State private var isExpanded = false

    var body: some View {
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 12))
                        Text("\(sources.count) Source\(sources.count == 1 ? "" : "s")")
                            .font(AppTypography.labelSmall())
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(AppColors.signalMercury)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.signalMercury.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())

                // Expanded sources list
                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(sources) { source in
                            MessageSourceRow(source: source)
                        }
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

// MARK: - Message Source Row

private struct MessageSourceRow: View {
    let source: MessageGroundingSource

    var body: some View {
        if let url = URL(string: source.url) {
            Link(destination: url) {
                HStack(spacing: 8) {
                    // Icon based on source type
                    Image(systemName: source.sourceType == .maps ? "map" : "globe")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textTertiary)
                        .frame(width: 20)

                    // Title
                    Text(source.title)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalLichen)
                        .lineLimit(1)

                    Spacer()

                    // External link indicator
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(6)
            }
        }
    }
}

// MARK: - Grounding Sources View (for GroundingChunk from Gemini)

struct GroundingSourcesView: View {
    let sources: [GroundingChunk]
    @State private var isExpanded = false

    var body: some View {
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 12))
                        Text("\(sources.count) Source\(sources.count == 1 ? "" : "s")")
                            .font(AppTypography.labelSmall())
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(AppColors.signalMercury)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.signalMercury.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())

                // Expanded sources list
                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(sources) { source in
                            SourceRow(source: source)
                        }
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

// MARK: - Source Row (for GroundingChunk)

private struct SourceRow: View {
    let source: GroundingChunk

    var body: some View {
        if let uri = source.uri, let url = URL(string: uri) {
            Link(destination: url) {
                HStack(spacing: 8) {
                    // Icon based on source type
                    Image(systemName: source.maps != nil ? "map" : "globe")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textTertiary)
                        .frame(width: 20)

                    // Title
                    Text(source.title)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalLichen)
                        .lineLimit(1)

                    Spacer()

                    // External link indicator
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(6)
            }
        }
    }
}

// MARK: - Compact Sources Badge

struct GroundingSourcesBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 4) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 10))
                Text("\(count)")
                    .font(AppTypography.labelSmall())
            }
            .foregroundColor(AppColors.signalMercury)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.signalMercury.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Memory Operations View

struct MemoryOperationsView: View {
    let operations: [MessageMemoryOperation]
    @State private var isExpanded = false

    private var successCount: Int {
        operations.filter { $0.success }.count
    }

    private var failureCount: Int {
        operations.filter { !$0.success }.count
    }

    var body: some View {
        if !operations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 12))

                        if failureCount > 0 {
                            Text("\(successCount) saved, \(failureCount) failed")
                                .font(AppTypography.labelSmall())
                        } else {
                            Text("\(operations.count) memor\(operations.count == 1 ? "y" : "ies") saved")
                                .font(AppTypography.labelSmall())
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(failureCount > 0 ? AppColors.signalHematite : AppColors.signalLichen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background((failureCount > 0 ? AppColors.signalHematite : AppColors.signalLichen).opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())

                // Expanded operations list
                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(operations) { operation in
                            MemoryOperationRow(operation: operation)
                        }
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

// MARK: - Memory Operation Row

private struct MemoryOperationRow: View {
    let operation: MessageMemoryOperation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Status icon
                Image(systemName: operation.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(operation.success ? AppColors.accentSuccess : AppColors.signalHematite)

                // Memory type badge
                Text(operation.memoryType.capitalized)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(operation.memoryType == "allocentric" ? AppColors.signalMercury : AppColors.signalLichen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        (operation.memoryType == "allocentric" ? AppColors.signalMercury : AppColors.signalLichen)
                            .opacity(0.2)
                    )
                    .cornerRadius(4)

                // Confidence
                Text("\(Int(operation.confidence * 100))%")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)

                Spacer()
            }

            // Content preview
            Text(operation.content)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)

            // Tags
            if !operation.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(operation.tags, id: \.self) { tag in
                            Text("#\(tag)")
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

            // Error message if failed
            if !operation.success, let error = operation.errorMessage {
                Text(error)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.signalHematite)
            }
        }
        .padding(10)
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }
}

// MARK: - Memory Operations Badge (compact)

struct MemoryOperationsBadge: View {
    let count: Int
    let hasFailures: Bool

    var body: some View {
        if count > 0 {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 10))
                Text("\(count)")
                    .font(AppTypography.labelSmall())
            }
            .foregroundColor(hasFailures ? AppColors.signalHematite : AppColors.signalLichen)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((hasFailures ? AppColors.signalHematite : AppColors.signalLichen).opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // MessageGroundingSource version (for chat bubbles)
        MessageSourcesView(sources: [
            MessageGroundingSource(title: "Example Article 1", url: "https://example.com/article1"),
            MessageGroundingSource(title: "Example Article 2 with a much longer title", url: "https://example.com/article2"),
            MessageGroundingSource(title: "Coffee Shop", url: "https://maps.google.com/?cid=123", sourceType: .maps)
        ])

        // GroundingChunk version (for Gemini responses)
        GroundingSourcesView(sources: [
            GroundingChunk(
                web: WebChunk(uri: "https://example.com/article1", title: "Example Article 1"),
                maps: nil
            ),
            GroundingChunk(
                web: WebChunk(uri: "https://example.com/article2", title: "Example Article 2 with a much longer title that should truncate"),
                maps: nil
            ),
            GroundingChunk(
                web: nil,
                maps: MapsChunk(uri: "https://maps.google.com/?cid=123", title: "Coffee Shop", placeId: "ChIJ...")
            )
        ])

        GroundingSourcesBadge(count: 5)

        // Memory operations
        MemoryOperationsView(operations: [
            MessageMemoryOperation(
                success: true,
                memoryType: "allocentric",
                content: "User prefers Swift over Objective-C for iOS development",
                tags: ["coding", "preferences", "swift"],
                confidence: 0.9
            ),
            MessageMemoryOperation(
                success: true,
                memoryType: "egoic",
                content: "User responds well to concise explanations with code examples",
                tags: ["communication", "style"],
                confidence: 0.8
            )
        ])

        // Failed operation
        MemoryOperationsView(operations: [
            MessageMemoryOperation(
                success: false,
                memoryType: "allocentric",
                content: "Some content that failed",
                tags: [],
                confidence: 0.7,
                errorMessage: "Invalid memory format"
            )
        ])

        MemoryOperationsBadge(count: 2, hasFailures: false)
    }
    .padding()
    .background(AppSurfaces.color(.contentBackground))
}
