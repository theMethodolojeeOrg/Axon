//
//  ReasoningView.swift
//  Axon
//
//  Collapsible view for displaying reasoning/thinking tokens from AI models.
//  Features a pulsating provider-colored logo when collapsed.
//

import SwiftUI

struct ReasoningView: View {
    let reasoning: String
    let providerColor: Color

    @State private var isExpanded = false
    @State private var isPulsing = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with pulsating logo
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                    if isExpanded {
                        isPulsing = false
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    // Pulsating Axon logo
                    PulsatingLogo(color: providerColor, isPulsing: isPulsing && !isExpanded)
                        .frame(width: 20, height: 20)

                    Text("Reasoning")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(providerColor)

                    Spacer()

                    // Token count indicator
                    Text("\(reasoning.split(separator: " ").count) tokens")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(providerColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(providerColor.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Expandable content
            if isExpanded {
                ScrollView {
                    Text(reasoning)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 300)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
    }
}

// MARK: - Pulsating Logo

struct PulsatingLogo: View {
    let color: Color
    let isPulsing: Bool

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            // Glow effect (only when pulsing)
            if isPulsing {
                Circle()
                    .fill(color.opacity(0.3))
                    .scaleEffect(scale * 1.5)
                    .opacity(opacity * 0.5)
            }

            // Main logo circle with axon-like design
            ZStack {
                Circle()
                    .fill(color)

                // Simple axon-inspired pattern (neurons/connections)
                Image(systemName: "brain.head.profile")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white)
                    .padding(4)
            }
            .scaleEffect(isPulsing ? scale : 1.0)
        }
        .onAppear {
            if isPulsing {
                startPulseAnimation()
            }
        }
        .onChange(of: isPulsing) { _, newValue in
            if newValue {
                startPulseAnimation()
            } else {
                stopPulseAnimation()
            }
        }
    }

    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: true)
        ) {
            scale = 1.15
            opacity = 0.7
        }
    }

    private func stopPulseAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            scale = 1.0
            opacity = 1.0
        }
    }
}

// MARK: - Preview

#Preview("Reasoning View") {
    VStack(spacing: 20) {
        ReasoningView(
            reasoning: """
            Let me think through this step by step:

            1. First, I need to understand what the user is asking for.
            2. They want to implement a new feature for reasoning token display.
            3. This requires creating a collapsible UI component.
            4. The component should have a pulsating logo in the provider's color.
            5. When expanded, it should show the full reasoning content.

            Now I'll proceed with the implementation...
            """,
            providerColor: Color.blue
        )

        ReasoningView(
            reasoning: "Quick reasoning check: The answer is 42.",
            providerColor: Color.orange
        )
    }
    .padding()
    #if os(macOS)
    .background(Color(NSColor.windowBackgroundColor))
    #else
    .background(Color(.systemBackground))
    #endif
}
