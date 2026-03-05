//
//  ConsoleStatusBar.swift
//  Axon
//
//  Status bar for developer console showing log counts.
//

import SwiftUI

struct ConsoleStatusBar: View {
    let filteredCount: Int
    let totalCount: Int
    let enabledCount: Int
    let totalCategories: Int
    let loggingEnabled: Bool

    var body: some View {
        HStack {
            // Log count
            Text("\(filteredCount) of \(totalCount) logs")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)

            Spacer()

            // Enabled categories
            Text("\(enabledCount)/\(totalCategories) categories")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)

            // Logging status
            Circle()
                .fill(loggingEnabled ? AppColors.signalLichen : AppColors.accentError)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(white: 0.1))
    }
}

#Preview {
    ConsoleStatusBar(
        filteredCount: 42,
        totalCount: 150,
        enabledCount: 8,
        totalCategories: 12,
        loggingEnabled: true
    )
    .background(Color.black)
}
