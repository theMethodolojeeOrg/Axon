import SwiftUI

struct LiveSessionOverlay: View {
    @StateObject private var liveService = LiveSessionService.shared
    @StateObject private var threadService = LiveSessionThreadService.shared
    @State private var showSaveConfirmation = false

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
                // Top bar with recording indicator
                HStack {
                    // Recording indicator
                    if threadService.isRecording {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("REC")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(8)
                    }

                    Spacer()

                    // Turn count
                    if threadService.turns.count > 0 {
                        Text("\(threadService.turns.count) turns")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

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

                // Playback controls (shown after session ends with recording)
                if liveService.status == .disconnected && liveService.currentRecording != nil {
                    playbackControls
                }

                // Main Controls
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

                    // Save to Thread (shown when recording available)
                    if liveService.currentRecording != nil {
                        Button(action: { showSaveConfirmation = true }) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Circle().fill(Color.blue.opacity(0.8)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .transition(.opacity)
        .alert("Save to Conversation?", isPresented: $showSaveConfirmation) {
            Button("Save") {
                saveAsConversation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save this Live session as a chat conversation? You'll be able to view it in your conversation history.")
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        VStack(spacing: 12) {
            // Progress bar
            if threadService.isPlaying {
                ProgressView(value: threadService.playbackProgress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .padding(.horizontal, 40)
            }

            HStack(spacing: 24) {
                // Play/Pause button
                Button(action: {
                    if threadService.isPlaying {
                        liveService.toggleRecordingPlayback()
                    } else {
                        liveService.playLastRecording()
                    }
                }) {
                    Image(systemName: threadService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.2)))
                }
                .buttonStyle(.plain)

                // Stop button
                if threadService.isPlaying {
                    Button(action: { liveService.stopRecordingPlayback() }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.white.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Current turn info during playback
            if threadService.isPlaying && threadService.currentPlaybackTurnIndex < threadService.turns.count {
                let turn = threadService.turns[threadService.currentPlaybackTurnIndex]
                HStack(spacing: 8) {
                    Image(systemName: turn.role == .user ? "person.fill" : "brain.head.profile")
                        .font(.system(size: 12))
                    Text(turn.transcript.prefix(50) + (turn.transcript.count > 50 ? "..." : ""))
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Save Action

    private func saveAsConversation() {
        Task {
            do {
                if let conversation = try await liveService.saveRecordingAsConversation() {
                    debugLog(.liveSession, "Saved Live session as conversation: \(conversation.id)")
                }
            } catch {
                debugLog(.liveSession, "Failed to save conversation: \(error.localizedDescription)")
            }
        }
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
