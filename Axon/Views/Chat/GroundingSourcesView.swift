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
                Button(action: { withAnimation { isExpanded.toggle() } }) {
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
                .background(AppColors.substrateSecondary)
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
                Button(action: { withAnimation { isExpanded.toggle() } }) {
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
                .background(AppColors.substrateSecondary)
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
    }
    .padding()
    .background(AppColors.substratePrimary)
}
