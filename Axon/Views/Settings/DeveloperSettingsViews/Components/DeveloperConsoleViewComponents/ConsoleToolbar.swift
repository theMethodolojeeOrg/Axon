//
//  ConsoleToolbar.swift
//  Axon
//
//  Toolbar for developer console with action buttons.
//

import SwiftUI

struct ConsoleToolbar: View {
    @Binding var isAutoScrollEnabled: Bool
    let onCopy: () -> Void
    let onClear: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            #if os(macOS)
            Text("Developer Console")
                .font(AppTypography.titleSmall())
                .foregroundColor(.white)
            #endif

            Spacer()

            // Auto-scroll toggle
            Button {
                isAutoScrollEnabled.toggle()
            } label: {
                Image(systemName: isAutoScrollEnabled ? "arrow.down.to.line.compact" : "arrow.down.to.line")
                    .foregroundColor(isAutoScrollEnabled ? AppColors.signalLichen : .gray)
            }
            .buttonStyle(.plain)
            .help("Auto-scroll to new logs")

            // Copy all
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .help("Copy all logs")

            // Clear
            Button(action: onClear) {
                Image(systemName: "trash")
                    .foregroundColor(AppColors.accentError)
            }
            .buttonStyle(.plain)
            .help("Clear logs")

            #if os(macOS)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            #endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(white: 0.1))
    }
}

#Preview {
    ConsoleToolbar(
        isAutoScrollEnabled: .constant(true),
        onCopy: {},
        onClear: {},
        onClose: {}
    )
    .background(Color.black)
}
