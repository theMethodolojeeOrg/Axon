//
//  SoloThreadToolbar.swift
//  Axon
//
//  Toolbar shown during active solo thread sessions.
//  Replaces MessageInputBar and provides pause/take-over controls.
//

import SwiftUI

struct SoloThreadToolbar: View {
    let conversation: Conversation
    let onPause: () -> Void
    let onTakeOver: () -> Void
    
    @StateObject private var soloService = SoloThreadService.shared
    @State private var showTakeOverConfirmation = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Status indicator
            statusView
            
            Spacer()
            
            // Pause button
            Button(action: onPause) {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 20))
                    Text("Pause")
                        .font(AppTypography.labelMedium())
                }
                .foregroundColor(AppColors.signalCopper)
            }
            .buttonStyle(.plain)
            
            // Take over button
            Button(action: { showTakeOverConfirmation = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 20))
                    Text("Take Over")
                        .font(AppTypography.labelMedium())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.signalMercury)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.substrateSecondary.opacity(0.95))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .confirmationDialog(
            "Take Over Conversation",
            isPresented: $showTakeOverConfirmation,
            titleVisibility: .visible
        ) {
            Button("Take Over", role: .destructive) {
                onTakeOver()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will end the solo session and convert this to a normal conversation. You can then chat normally.")
        }
    }
    
    // MARK: - Status View
    
    private var statusView: some View {
        HStack(spacing: 10) {
            // Pulsing indicator when active
            pulsingIndicator
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Solo Session")
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.textPrimary)
                    
                    statusBadge
                }
                
                if let config = soloService.getSoloConfig(for: conversation.id) {
                    Text("Turn \(config.turnsUsed) of \(config.turnsAllocated)")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }
    
    private var pulsingIndicator: some View {
        ZStack {
            // Outer pulse
            Circle()
                .fill(statusColor.opacity(0.3))
                .frame(width: 16, height: 16)
                .scaleEffect(isActive ? 1.5 : 1.0)
                .opacity(isActive ? 0 : 0.6)
                .animation(
                    isActive ? Animation.easeOut(duration: 1.2).repeatForever(autoreverses: false) : .default,
                    value: isActive
                )
            
            // Inner dot
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
        }
    }
    
    private var statusBadge: some View {
        Group {
            if let config = soloService.getSoloConfig(for: conversation.id) {
                Text(config.status.displayName)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor)
                    .cornerRadius(4)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var isActive: Bool {
        soloService.getSoloConfig(for: conversation.id)?.status == .active
    }
    
    private var statusColor: Color {
        guard let config = soloService.getSoloConfig(for: conversation.id) else {
            return AppColors.textTertiary
        }
        
        switch config.status {
        case .active:
            return AppColors.signalLichen
        case .paused, .awaitingReview:
            return AppColors.signalSaturn
        case .completed:
            return AppColors.signalMercury
        case .userTookOver:
            return AppColors.signalMercuryLight
        case .budgetExhausted, .error:
            return AppColors.signalCopper
        }
    }
}

// MARK: - Solo Thread Status Bar (Compact version for top of chat)

struct SoloThreadStatusBar: View {
    let conversation: Conversation
    @StateObject private var soloService = SoloThreadService.shared
    
    var body: some View {
        if let config = soloService.getSoloConfig(for: conversation.id) {
            HStack(spacing: 8) {
                Image(systemName: config.status.icon)
                    .font(.system(size: 14))
                    .foregroundColor(statusColor(for: config.status))
                
                Text("Solo Session")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
                
                Text("•")
                    .foregroundColor(AppColors.textTertiary)
                
                Text("Turn \(config.turnsUsed)/\(config.turnsAllocated)")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
                
                if config.extensionCount > 0 {
                    Text("•")
                        .foregroundColor(AppColors.textTertiary)
                    
                    Text("+\(config.extensionCount) ext")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalMercury)
                }
                
                Spacer()
                
                // Duration
                Text(formatDuration(config.duration))
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.substrateSecondary.opacity(0.8))
        }
    }
    
    private func statusColor(for status: SoloThreadStatus) -> Color {
        switch status {
        case .active:
            return AppColors.signalLichen
        case .paused, .awaitingReview:
            return AppColors.signalSaturn
        case .completed:
            return AppColors.signalMercury
        case .userTookOver:
            return AppColors.signalMercuryLight
        case .budgetExhausted, .error:
            return AppColors.signalCopper
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        SoloThreadToolbar(
            conversation: Conversation(
                id: "test",
                title: "Test Solo Thread",
                projectId: "default",
                soloThreadConfig: SoloThreadConfig.newSession(
                    turnsAllocated: 5,
                    sessionIndex: 1
                )
            ),
            onPause: {},
            onTakeOver: {}
        )
    }
    .background(AppColors.substratePrimary)
}
