//
//  LogCategoryToggleButton.swift
//  Axon
//
//  Three-state toggle button for log category groups.
//

import SwiftUI

struct LogCategoryToggleButton: View {
    let state: LogCategoryToggleState
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
                    .frame(width: 24, height: 24)

                if state != .allDisabled {
                    Image(systemName: state == .allEnabled ? "checkmark" : "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch state {
        case .allEnabled:
            return AppColors.signalLichen
        case .partiallyEnabled:
            return AppColors.signalCopper
        case .allDisabled:
            return AppColors.textDisabled.opacity(0.3)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        LogCategoryToggleButton(state: .allEnabled, onToggle: {})
        LogCategoryToggleButton(state: .partiallyEnabled, onToggle: {})
        LogCategoryToggleButton(state: .allDisabled, onToggle: {})
    }
}
