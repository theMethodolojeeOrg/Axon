//
//  ModelTuningSearchBar.swift
//  Axon
//
//  Search bar component for filtering models.
//

import SwiftUI

struct ModelTuningSearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textTertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(AppColors.textPrimary)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}
