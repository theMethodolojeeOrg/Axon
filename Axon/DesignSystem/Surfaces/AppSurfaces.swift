//
//  AppSurfaces.swift
//  Axon
//
//  Semantic surface roles layered over the raw AppColors palette.
//

import SwiftUI

enum AppSurfaceRole {
    case windowBackground
    case contentBackground
    case sidebarBackground
    case sidebarHeaderBackground
    case cardBackground
    case cardBorder
    case controlBackground
    case controlMutedBackground
    case inputBackground
    case selectedBackground
    case selectedBorder
    case overlayBackground
    case transientBackground
    case separator
}

enum AppSurfaces {
    static func color(_ role: AppSurfaceRole) -> Color {
        switch role {
        case .windowBackground, .contentBackground:
            return AppColors.substratePrimary
        case .sidebarBackground:
            return AppColors.substrateSecondary
        case .sidebarHeaderBackground, .cardBackground, .inputBackground, .overlayBackground:
            return AppColors.substrateSecondary
        case .controlBackground:
            return AppColors.substrateTertiary
        case .controlMutedBackground:
            return AppColors.substrateTertiary.opacity(0.5)
        case .selectedBackground:
            return AppColors.signalMercury.opacity(0.12)
        case .selectedBorder:
            return AppColors.signalMercury.opacity(0.35)
        case .cardBorder:
            return AppColors.glassBorder
        case .transientBackground:
            return AppColors.substrateSecondary.opacity(0.95)
        case .separator:
            return AppColors.divider
        }
    }
}

private struct AppSurfaceModifier: ViewModifier {
    let role: AppSurfaceRole

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        if role == .sidebarBackground {
            content.background(.bar)
        } else {
            content.background(AppSurfaces.color(role))
        }
        #else
        content.background(AppSurfaces.color(role))
        #endif
    }
}

private struct AppRoundedSurfaceModifier: ViewModifier {
    let role: AppSurfaceRole
    let radius: CGFloat
    let border: Color?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(AppSurfaces.color(role))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius)
                            .stroke(border ?? .clear, lineWidth: border == nil ? 0 : 1)
                    )
            )
    }
}

private struct AppMaterialSurfaceModifier: ViewModifier {
    let radius: CGFloat
    let border: Color?

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border ?? .clear, lineWidth: border == nil ? 0 : 1)
            )
    }
}

private struct AppSheetMaterialModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationBackground(.ultraThinMaterial)
            .presentationCornerRadius(24)
    }
}

extension View {
    func appSurface(_ role: AppSurfaceRole) -> some View {
        modifier(AppSurfaceModifier(role: role))
    }

    func appRoundedSurface(
        _ role: AppSurfaceRole,
        radius: CGFloat = 8,
        border: Color? = nil
    ) -> some View {
        modifier(AppRoundedSurfaceModifier(role: role, radius: radius, border: border))
    }

    func appMaterialSurface(
        radius: CGFloat = 12,
        border: Color? = AppSurfaces.color(.cardBorder)
    ) -> some View {
        modifier(AppMaterialSurfaceModifier(radius: radius, border: border))
    }

    func appSheetMaterial() -> some View {
        modifier(AppSheetMaterialModifier())
    }
}
