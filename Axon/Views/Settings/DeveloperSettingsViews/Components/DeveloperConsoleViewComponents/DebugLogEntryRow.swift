//
//  DebugLogEntryRow.swift
//  Axon
//
//  Individual log entry row for developer console.
//

import SwiftUI

struct DebugLogEntryRow: View {
    let entry: DebugLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(entry.formattedTimestamp)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 85, alignment: .leading)

            // Category badge
            Text(entry.category.rawValue)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(categoryColor(for: entry.category))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(categoryColor(for: entry.category).opacity(0.2))
                .cornerRadius(4)
                .frame(width: 140, alignment: .leading)

            // Message
            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func categoryColor(for category: LogCategory) -> Color {
        switch category.group {
        case .security: return .orange
        case .data: return .blue
        case .sync: return .cyan
        case .config: return .purple
        case .services: return .green
        case .media: return .pink
        case .tools: return .yellow
        case .chat: return .teal
        case .developer: return .red
        case .aip: return .indigo
        }
    }
}

#Preview {
    VStack {
        DebugLogEntryRow(entry: DebugLogEntry(
            timestamp: Date(),
            category: .developerSettings,
            message: "Test log message"
        ))
    }
    .background(Color.black)
}
