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
            
            VStack(spacing: 32) {
                Spacer()
                
                // Status
                Text(statusText)
                    .font(AppTypography.titleMedium())
                    .foregroundColor(.white)
                
                // Simple Visualizer
                HStack(spacing: 8) {
                    // Input Level (Mic)
                    Capsule()
                        .fill(Color.green)
                        .frame(width: 8, height: 20 + CGFloat(liveService.inputLevel * 200))
                        .animation(.spring(response: 0.1), value: liveService.inputLevel)
                    
                    // Output Level (Speaker)
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: 8, height: 20 + CGFloat(liveService.outputLevel * 200))
                        .animation(.spring(response: 0.1), value: liveService.outputLevel)
                }
                .frame(height: 100)
                
                // Transcript / Feedback
                if !liveService.latestTranscript.isEmpty {
                    Text(liveService.latestTranscript)
                        .font(AppTypography.bodyLarge())
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .lineLimit(4)
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
