import SwiftUI

struct LiveSessionOverlay: View {
    @StateObject private var liveService = LiveSessionService.shared

    var body: some View {
        ZStack {
            #if os(macOS)
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
            #else
            Color.black.opacity(0.95)
                .edgesIgnoringSafeArea(.all)
            #endif

            VStack(spacing: 24) {
                Spacer()

                // Execution Mode Badge
                if let mode = liveService.activeExecutionMode {
                    executionModeBadge(mode: mode)
                }

                // Status
                Text(statusText)
                    .font(AppTypography.titleMedium())
                    .foregroundColor(.white)

                // Simple Visualizer
                HStack(spacing: 8) {
                    // Input Level (Mic) - color indicates noise gate state
                    Capsule()
                        .fill(liveService.isNoiseGateOpen ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 8, height: 20 + CGFloat(liveService.inputLevel * 200))
                        .animation(.spring(response: 0.1), value: liveService.inputLevel)
                        .animation(.easeInOut(duration: 0.1), value: liveService.isNoiseGateOpen)

                    // Output Level (Speaker)
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: 8, height: 20 + CGFloat(liveService.outputLevel * 200))
                        .animation(.spring(response: 0.1), value: liveService.outputLevel)
                }
                .frame(height: 100)

                // Noise Gate Indicator
                if liveService.isNoiseGateOpen {
                    Text("Transmitting")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(8)
                        .transition(.opacity)
                }

                // Transcript / Feedback
                if !liveService.latestTranscript.isEmpty {
                    ScrollView {
                        Text(liveService.latestTranscript)
                            .font(AppTypography.bodyLarge())
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxHeight: 120)
                }

                // Capability Indicators
                if let capabilities = liveService.currentCapabilities {
                    capabilityIndicators(capabilities: capabilities)
                }

                Spacer()

                // Controls
                HStack(spacing: 40) {
                    // Mic Toggle
                    Button(action: { liveService.toggleMic() }) {
                        Image(systemName: liveService.isMicEnabled ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(Color.white.opacity(0.2)))
                    }
                    .buttonStyle(.plain)

                    // Hang Up
                    Button(action: { liveService.stopSession() }) {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .frame(width: 72, height: 72)
                            .background(Circle().fill(AppColors.accentError))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 40)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Execution Mode Badge

    private func executionModeBadge(mode: ExecutionMode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: modeIcon(for: mode))
                .font(.system(size: 12))
            Text(mode.displayName)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(modeColor(for: mode).opacity(0.3))
        .foregroundColor(modeColor(for: mode))
        .cornerRadius(12)
    }

    private func modeIcon(for mode: ExecutionMode) -> String {
        switch mode {
        case .cloudWebSocket:
            return "bolt.fill"
        case .cloudHTTPStreaming:
            return "cloud.fill"
        case .onDeviceMLX:
            return "cpu.fill"
        }
    }

    private func modeColor(for mode: ExecutionMode) -> Color {
        switch mode {
        case .cloudWebSocket:
            return .green
        case .cloudHTTPStreaming:
            return .blue
        case .onDeviceMLX:
            return .purple
        }
    }

    // MARK: - Capability Indicators

    private func capabilityIndicators(capabilities: LiveProviderCapabilities) -> some View {
        HStack(spacing: 16) {
            if capabilities.supportsRealtimeDuplex {
                capabilityChip(icon: "waveform", label: "Duplex", active: true)
            }

            if capabilities.supportsServerSideVAD {
                capabilityChip(icon: "ear.fill", label: "Server VAD", active: true)
            } else {
                capabilityChip(icon: "ear.fill", label: "Local VAD", active: true)
            }

            if capabilities.supportsFunctionCalling {
                capabilityChip(icon: "function", label: "Tools", active: true)
            }
        }
        .padding(.horizontal)
    }

    private func capabilityChip(icon: String, label: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 10))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(active ? Color.white.opacity(0.15) : Color.gray.opacity(0.1))
        .foregroundColor(active ? .white : .gray)
        .cornerRadius(8)
    }

    // MARK: - Status Text

    var statusText: String {
        switch liveService.status {
        case .connecting: return "Connecting..."
        case .connected: return "Live Session Active"
        case .disconnected: return "Disconnected"
        case .error(let msg): return "Error: \(msg)"
        case .idle: return "Ready"
        }
    }
}

#if os(macOS)
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}
#endif
