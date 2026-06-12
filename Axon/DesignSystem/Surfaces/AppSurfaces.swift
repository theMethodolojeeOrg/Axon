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

enum AppSheetSize {
    case compactForm
    case form
    case detail
    case browser

    #if os(macOS)
    var macFrame: (minWidth: CGFloat, idealWidth: CGFloat, minHeight: CGFloat, idealHeight: CGFloat) {
        switch self {
        case .compactForm:
            return (420, 480, 260, 340)
        case .form:
            return (480, 560, 500, 650)
        case .detail:
            return (560, 680, 540, 720)
        case .browser:
            return (640, 760, 560, 720)
        }
    }
    #endif
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

private struct AppSizedSheetModifier: ViewModifier {
    let size: AppSheetSize

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        let frame = size.macFrame
        content
            .frame(
                minWidth: frame.minWidth,
                idealWidth: frame.idealWidth,
                minHeight: frame.minHeight,
                idealHeight: frame.idealHeight
            )
            .appSheetMaterial()
        #else
        switch size {
        case .compactForm, .form:
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .appSheetMaterial()
        case .detail, .browser:
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .appSheetMaterial()
        }
        #endif
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

    func appSizedSheet(_ size: AppSheetSize = .form) -> some View {
        modifier(AppSizedSheetModifier(size: size))
    }
}
