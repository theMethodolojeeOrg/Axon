//
//  CognitionView.swift
//  Axon
//
//  Combined view for Memory, Thinking (Internal Thread), Heuristics, and Issues with tab navigation.
//

import SwiftUI

struct CognitionView: View {
    @State private var selectedTab: CognitionTab = .memory
    @ObservedObject private var memoryViewModel = MemoryViewModel.shared
    @ObservedObject private var threadViewModel = InternalThreadViewModel.shared
    @ObservedObject private var heuristicsViewModel = HeuristicsViewModel.shared

    enum CognitionTab: String, CaseIterable, Identifiable {
        case memory = "Memory"
        case thinking = "Thinking"
        case heuristics = "Heuristics"
        case issues = "Issues"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .memory: return "brain.fill"
            case .thinking: return "note.text"
            case .heuristics: return "sparkles"
            case .issues: return "exclamationmark.triangle.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            AppColors.substratePrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab selector row
                cognitionTabSelector

                Divider()
                    .background(AppColors.divider)

                // Tab content
                switch selectedTab {
                case .memory:
                    MemoryContentView()
                        .environmentObject(memoryViewModel)
                case .thinking:
                    InternalThreadContentView()
                        .environmentObject(threadViewModel)
                case .heuristics:
                    HeuristicsContentView()
                        .environmentObject(heuristicsViewModel)
                case .issues:
                    MemoryIssuesContentView()
                        .environmentObject(memoryViewModel)
                }
            }
        }
        // Toast overlays from MemoryViewModel (shown on memory or issues tab)
        .overlay(alignment: .top) {
            if selectedTab == .memory || selectedTab == .issues {
                if let successMessage = memoryViewModel.successMessage {
                    MemorySuccessToast(message: successMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture {
                            memoryViewModel.successMessage = nil
                        }
                }

                if let errorMessage = memoryViewModel.error {
                    MemoryErrorToast(message: errorMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture {
                            memoryViewModel.error = nil
                        }
                }
            }
        }
        .animation(AppAnimations.standardEasing, value: memoryViewModel.successMessage != nil)
        .animation(AppAnimations.standardEasing, value: memoryViewModel.error != nil)
        .onAppear {
            // Detect memory issues when view appears
            memoryViewModel.detectIssues()
        }
    }

    private var cognitionTabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(CognitionTab.allCases) { tab in
                    if tab == .issues {
                        // Issues tab with badge
                        CognitionTabButtonWithBadge(
                            title: tab.rawValue,
                            icon: tab.icon,
                            isSelected: selectedTab == tab,
                            badgeCount: memoryViewModel.issueCount
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        }
                    } else {
                        CognitionTabButton(
                            title: tab.rawValue,
                            icon: tab.icon,
                            isSelected: selectedTab == tab
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(AppColors.substrateSecondary)
    }
}

// MARK: - Tab Button

struct CognitionTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(AppTypography.titleSmall())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury : AppColors.substrateTertiary)
            )
            .foregroundColor(isSelected ? .white : AppColors.textSecondary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Tab Button with Badge

struct CognitionTabButtonWithBadge: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let badgeCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(badgeCount > 0 && !isSelected ? AppColors.signalCopper : nil)
                Text(title)
                    .font(AppTypography.titleSmall())

                // Badge
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? .white.opacity(0.3) : AppColors.signalCopper)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury : AppColors.substrateTertiary)
            )
            .foregroundColor(isSelected ? .white : AppColors.textSecondary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    CognitionView()
}
