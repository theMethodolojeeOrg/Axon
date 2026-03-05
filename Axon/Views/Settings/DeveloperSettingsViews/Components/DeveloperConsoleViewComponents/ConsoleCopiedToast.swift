//
//  ConsoleCopiedToast.swift
//  Axon
//
//  Toast notification for copy action in developer console.
//

import SwiftUI

struct ConsoleCopiedToast: View {
    @Binding var isVisible: Bool

    var body: some View {
        Group {
            if isVisible {
                VStack {
                    Spacer()
                    Text("Copied to clipboard")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AppColors.signalLichen)
                        .cornerRadius(8)
                        .padding(.bottom, 60)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isVisible)
    }
}

#Preview {
    ConsoleCopiedToast(isVisible: .constant(true))
        .background(Color.black)
}
