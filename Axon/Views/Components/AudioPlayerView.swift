//
//  AudioPlayerView.swift
//  Axon
//
//  Audio player UI component with play/pause/seek controls
//

import SwiftUI

struct AudioPlayerView: View {
    @ObservedObject var ttsService: TTSPlaybackService

    var body: some View {
        VStack {
            if ttsService.isGenerating || ttsService.currentMessageId != nil {
                HStack(spacing: 16) {
                    if ttsService.isGenerating {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [AppColors.signalMercury.opacity(0.2), AppColors.signalMercury.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)

                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.signalMercury))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Generating audio…")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)
                            Text("Hang tight while we prepare playback")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                    } else {
                        // Play/Pause button
                        Button(action: {
                            if ttsService.isPlaying {
                                ttsService.pause()
                            } else {
                                ttsService.resume()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [AppColors.signalMercury, AppColors.signalMercury.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                    .shadow(color: AppColors.signalMercury.opacity(0.3), radius: 8, x: 0, y: 4)
                                
                                Image(systemName: ttsService.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AppColors.substratePrimary)
                            }
                        }
                        .buttonStyle(ScaleButtonStyle())

                        // Time and progress
                        VStack(spacing: 6) {
                            // Progress slider
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background track
                                    Capsule()
                                        .fill(AppColors.textTertiary.opacity(0.2))
                                        .frame(height: 6)

                                    // Progress track
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [AppColors.signalMercury, AppColors.signalMercury.opacity(0.7)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(0, min(geometry.size.width * CGFloat(ttsService.currentTime / max(ttsService.duration, 0.1)), geometry.size.width)), height: 6)
                                }
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let percentage = value.location.x / geometry.size.width
                                            let newTime = min(max(0, percentage * ttsService.duration), ttsService.duration)
                                            ttsService.seek(to: newTime)
                                        }
                                )
                            }
                            .frame(height: 6)

                            // Time labels
                            HStack {
                                Text(formatTime(ttsService.currentTime))
                                    .font(AppTypography.labelSmall().monospacedDigit())
                                    .foregroundColor(AppColors.textSecondary)

                                Spacer()

                                Text(formatTime(ttsService.duration))
                                    .font(AppTypography.labelSmall().monospacedDigit())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }

                    // Close button (available during loading and playback)
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            ttsService.stop()
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppColors.textSecondary)
                            .padding(8)
                            .background(AppColors.textTertiary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .background(AppColors.substrateSecondary.opacity(0.5))
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(AppColors.textTertiary.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 15, x: 0, y: 5)
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: ttsService.currentMessageId)
        .animation(.easeInOut(duration: 0.2), value: ttsService.isPlaying)
        .animation(.easeInOut(duration: 0.2), value: ttsService.isGenerating)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    #Preview {
        AudioPlayerView(ttsService: TTSPlaybackService.shared)
            .background(AppColors.substratePrimary)
    }
}
