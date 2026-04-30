//
//  AudioPlayerView.swift
//  Axon
//
//  Audio player UI component with play/pause/seek controls
//

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AudioPlayerView: View {
    @ObservedObject var ttsService: TTSPlaybackService
    @State private var showingSaveSuccess = false
    @State private var saveError: String?

    var body: some View {
        VStack {
            let _ = debugLog(.ttsPlayback, "🔊 [AudioPlayerView] isGenerating=\(ttsService.isGenerating), currentMessageId=\(ttsService.currentMessageId ?? "nil")")
            if ttsService.isGenerating || ttsService.currentMessageId != nil {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        if ttsService.isGenerating {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [AppColors.signalMercury.opacity(0.25), AppColors.signalMercury.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 48, height: 48)

                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.signalMercury))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Generating audio")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.textPrimary)
                                Text("Preparing playback")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            Spacer()
                        } else {
                            Button(action: {
                                if ttsService.isPlaying {
                                    ttsService.pause()
                                } else {
                                    ttsService.resume()
                                }
                            }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [AppColors.signalMercury, AppColors.signalMercury.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 52, height: 52)
                                        .shadow(color: AppColors.signalMercury.opacity(0.28), radius: 10, x: 0, y: 6)

                                    Image(systemName: ttsService.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(AppSurfaces.color(.contentBackground))
                                }
                            }
                            .buttonStyle(ScaleButtonStyle())

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(ttsService.isPlaying ? "Now playing" : "Paused")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.textSecondary)

                                    Text("•")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.textTertiary)

                                    Text(formatTime(ttsService.currentTime))
                                        .font(AppTypography.labelSmall().monospacedDigit())
                                        .foregroundColor(AppColors.textSecondary)
                                }

                                GeometryReader { geometry in
                                    let fraction = progressFraction(current: ttsService.currentTime, duration: ttsService.duration)
                                    let knobX = min(max(0, geometry.size.width * CGFloat(fraction) - 6), geometry.size.width - 12)
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(AppColors.textTertiary.opacity(0.16))
                                            .frame(height: 8)

                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [AppColors.signalMercury, AppColors.signalMercury.opacity(0.6)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: max(0, min(geometry.size.width * CGFloat(fraction), geometry.size.width)), height: 8)

                                        Circle()
                                            .fill(AppSurfaces.color(.contentBackground))
                                            .frame(width: 12, height: 12)
                                            .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
                                            .offset(x: knobX)
                                    }
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                let percentage = value.location.x / geometry.size.width
                                                let newTime = min(max(0, percentage * ttsService.duration), ttsService.duration)
                                                ttsService.seek(to: newTime)
                                            }
                                    )
                                }
                                .frame(height: 12)
                            }

                            Spacer()
                        }

                        HStack(spacing: 8) {
                            if !ttsService.isGenerating {
                                Button(action: saveAudio) {
                                    Image(systemName: showingSaveSuccess ? "checkmark" : "square.and.arrow.down")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(showingSaveSuccess ? AppColors.accentSuccess : AppColors.textSecondary)
                                        .padding(9)
                                        .background(AppColors.textTertiary.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(ScaleButtonStyle())
                                .disabled(showingSaveSuccess)
                            }

                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    ttsService.stop()
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(AppColors.textSecondary)
                                    .padding(9)
                                    .background(AppColors.textTertiary.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                    }

                    if !ttsService.isGenerating {
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
                .padding(16)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(AppSurfaces.color(.cardBackground).opacity(0.35))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(AppColors.textTertiary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
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

    private func progressFraction(current: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(current / duration, 0), 1)
    }

    private func saveAudio() {
        guard let audioExport = ttsService.getCurrentAudioForExport() else {
            saveError = "No audio available to save"
            return
        }

        #if os(iOS)
        saveAudioiOS(data: audioExport.data, filename: audioExport.suggestedFilename)
        #elseif os(macOS)
        saveAudioMacOS(data: audioExport.data, filename: audioExport.suggestedFilename)
        #endif
    }

    #if os(iOS)
    private func saveAudioiOS(data: Data, filename: String) {
        // Create a temporary file for sharing
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: tempURL)

            // Present share sheet
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)

            // Find the key window scene
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                // Handle iPad popover
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = rootViewController.view
                    popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }

                rootViewController.present(activityVC, animated: true) {
                    // Show success feedback
                    withAnimation {
                        showingSaveSuccess = true
                    }
                    // Reset after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showingSaveSuccess = false
                        }
                    }
                }
            }
        } catch {
            saveError = "Failed to save audio: \(error.localizedDescription)"
        }
    }
    #endif

    #if os(macOS)
    private func saveAudioMacOS(data: Data, filename: String) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.audio]
        savePanel.nameFieldStringValue = filename
        savePanel.title = "Save Audio File"
        savePanel.message = "Choose where to save the TTS audio file"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try data.write(to: url)
                    DispatchQueue.main.async {
                        withAnimation {
                            showingSaveSuccess = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showingSaveSuccess = false
                            }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        saveError = "Failed to save: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    #endif
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    #Preview {
        AudioPlayerView(ttsService: TTSPlaybackService.shared)
            .background(AppSurfaces.color(.contentBackground))
    }
}
