//
//  ConsoleEmptyState.swift
//  Axon
//
//  Empty state display for developer console.
//

import SwiftUI

struct ConsoleEmptyState: View {
    let logEntries: [DebugLogEntry]
    let loggingEnabled: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text(logEntries.isEmpty ? "No logs yet" : "No matching logs")
                .font(AppTypography.bodySmall())
                .foregroundColor(.gray)

            if !loggingEnabled {
                Text("Enable logging in Developer Settings")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.signalMercury)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ConsoleEmptyState(
        logEntries: [],
        loggingEnabled: false
    )
    .background(Color.black)
}
