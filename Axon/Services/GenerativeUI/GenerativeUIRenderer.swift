//
//  GenerativeUIRenderer.swift
//  Axon
//
//  JSON-to-SwiftUI rendering engine for generative UI
//

import SwiftUI

// MARK: - Renderer

/// Renders GenerativeUINode trees into SwiftUI views
/// Uses AnyView for type erasure to avoid Swift type checker hanging on complex recursive generics
struct GenerativeUIRenderer {

    // MARK: - Main Render Function

    /// Render a node tree into a SwiftUI view
    static func render(_ node: GenerativeUINode) -> AnyView {
        switch node.type {
        case .vstack:
            return renderVStack(node)
        case .hstack:
            return renderHStack(node)
        case .zstack:
            return renderZStack(node)
        case .text:
            return renderText(node)
        case .button:
            return renderButton(node)
        case .spacer:
            return renderSpacer(node)
        case .divider:
            return AnyView(Divider())
        case .image:
            return renderImage(node)
        }
    }

    // MARK: - Layout Components

    private static func renderVStack(_ node: GenerativeUINode) -> AnyView {
        let spacing = node.properties["spacing"]?.doubleValue ?? 8
        let alignment = resolveHorizontalAlignment(node.properties["alignment"]?.stringValue)

        return AnyView(
            VStack(alignment: alignment, spacing: spacing) {
                ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
                    render(child)
                }
            }
        )
    }

    private static func renderHStack(_ node: GenerativeUINode) -> AnyView {
        let spacing = node.properties["spacing"]?.doubleValue ?? 8
        let alignment = resolveVerticalAlignment(node.properties["alignment"]?.stringValue)

        return AnyView(
            HStack(alignment: alignment, spacing: spacing) {
                ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
                    render(child)
                }
            }
        )
    }

    private static func renderZStack(_ node: GenerativeUINode) -> AnyView {
        let alignment = resolveAlignment(node.properties["alignment"]?.stringValue)

        return AnyView(
            ZStack(alignment: alignment) {
                ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
                    render(child)
                }
            }
        )
    }

    // MARK: - Basic Components

    private static func renderText(_ node: GenerativeUINode) -> AnyView {
        let text = node.properties["text"]?.stringValue ?? ""
        let font = resolveFont(node.properties["font"]?.stringValue)
        let color = resolveColor(node.properties["color"]?.stringValue)

        return AnyView(
            Text(text)
                .font(font)
                .foregroundColor(color)
        )
    }

    private static func renderButton(_ node: GenerativeUINode) -> AnyView {
        let label = node.properties["label"]?.stringValue ?? "Button"

        // Check if button has custom content (children)
        if let children = node.children, !children.isEmpty {
            return AnyView(
                Button(action: { /* Action handled externally in future */ }) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        render(child)
                    }
                }
                .buttonStyle(.borderedProminent)
            )
        } else {
            return AnyView(
                Button(label) { /* Action handled externally in future */ }
                    .buttonStyle(.borderedProminent)
            )
        }
    }

    private static func renderSpacer(_ node: GenerativeUINode) -> AnyView {
        if let minLength = node.properties["minLength"]?.doubleValue {
            return AnyView(Spacer(minLength: minLength))
        } else {
            return AnyView(Spacer())
        }
    }

    private static func renderImage(_ node: GenerativeUINode) -> AnyView {
        let color = resolveColor(node.properties["color"]?.stringValue)

        if let systemName = node.properties["systemName"]?.stringValue {
            // SF Symbol
            return AnyView(
                Image(systemName: systemName)
                    .foregroundColor(color)
            )
        } else if let assetName = node.properties["name"]?.stringValue {
            // Asset catalog image
            return AnyView(
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            )
        } else {
            // Placeholder for missing image
            return AnyView(
                Image(systemName: "photo")
                    .foregroundColor(AppColors.textTertiary)
            )
        }
    }

    // MARK: - Resolution Helpers

    /// Resolve font name to AppTypography font
    static func resolveFont(_ name: String?) -> Font {
        guard let name = name else { return AppTypography.bodyMedium() }

        switch name.lowercased() {
        // Display
        case "displaylarge": return AppTypography.displayLarge()
        case "displaymedium": return AppTypography.displayMedium()
        case "displaysmall": return AppTypography.displaySmall()

        // Headline
        case "headlinelarge": return AppTypography.headlineLarge()
        case "headlinemedium": return AppTypography.headlineMedium()
        case "headlinesmall": return AppTypography.headlineSmall()

        // Title
        case "titlelarge", "title": return AppTypography.titleLarge()
        case "titlemedium": return AppTypography.titleMedium()
        case "titlesmall": return AppTypography.titleSmall()

        // Body
        case "bodylarge": return AppTypography.bodyLarge()
        case "bodymedium", "body": return AppTypography.bodyMedium()
        case "bodysmall": return AppTypography.bodySmall()

        // Label
        case "labellarge": return AppTypography.labelLarge()
        case "labelmedium": return AppTypography.labelMedium()
        case "labelsmall", "caption": return AppTypography.labelSmall()

        // Code
        case "code": return AppTypography.code()
        case "codesmall": return AppTypography.codeSmall()

        default: return AppTypography.bodyMedium()
        }
    }

    /// Resolve color name to AppColors color
    static func resolveColor(_ name: String?) -> Color {
        guard let name = name else { return AppColors.textPrimary }

        switch name.lowercased() {
        // Text
        case "textprimary", "primary": return AppColors.textPrimary
        case "textsecondary", "secondary": return AppColors.textSecondary
        case "texttertiary", "tertiary": return AppColors.textTertiary
        case "textdisabled", "disabled": return AppColors.textDisabled

        // Signals
        case "mercury", "signalmercury": return AppColors.signalMercury
        case "lichen", "signallichen": return AppColors.signalLichen
        case "copper", "signalcopper": return AppColors.signalCopper
        case "hematite", "signalhematite": return AppColors.signalHematite
        case "saturn", "signalsaturn": return AppColors.signalSaturn

        // Accents
        case "accentprimary", "accent": return AppColors.accentPrimary
        case "accentsuccess", "success": return AppColors.accentSuccess
        case "accentwarning", "warning": return AppColors.accentWarning
        case "accenterror", "error": return AppColors.accentError

        // Substrate
        case "substrateprimary": return AppColors.substratePrimary
        case "substratesecondary": return AppColors.substrateSecondary
        case "substratetertiary": return AppColors.substrateTertiary
        case "substrateelevated": return AppColors.substrateElevated

        // Standard colors
        case "white": return .white
        case "black": return .black
        case "clear": return .clear
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "orange": return .orange
        case "yellow": return .yellow
        case "purple": return .purple
        case "pink": return .pink
        case "gray", "grey": return .gray

        default: return AppColors.textPrimary
        }
    }

    /// Resolve horizontal alignment string to SwiftUI alignment
    private static func resolveHorizontalAlignment(_ name: String?) -> HorizontalAlignment {
        guard let name = name else { return .center }

        switch name.lowercased() {
        case "leading", "left": return .leading
        case "trailing", "right": return .trailing
        case "center": return .center
        default: return .center
        }
    }

    /// Resolve vertical alignment string to SwiftUI alignment
    private static func resolveVerticalAlignment(_ name: String?) -> VerticalAlignment {
        guard let name = name else { return .center }

        switch name.lowercased() {
        case "top": return .top
        case "bottom": return .bottom
        case "center": return .center
        case "firsttextbaseline": return .firstTextBaseline
        case "lasttextbaseline": return .lastTextBaseline
        default: return .center
        }
    }

    /// Resolve ZStack alignment
    private static func resolveAlignment(_ name: String?) -> Alignment {
        guard let name = name else { return .center }

        switch name.lowercased() {
        case "topleft", "topleading": return .topLeading
        case "top": return .top
        case "topright", "toptrailing": return .topTrailing
        case "left", "leading": return .leading
        case "center": return .center
        case "right", "trailing": return .trailing
        case "bottomleft", "bottomleading": return .bottomLeading
        case "bottom": return .bottom
        case "bottomright", "bottomtrailing": return .bottomTrailing
        default: return .center
        }
    }
}

// MARK: - Preview Helper

/// A view that wraps the renderer for previewing
struct GenerativeUIPreview: View {
    let node: GenerativeUINode

    var body: some View {
        GenerativeUIRenderer.render(node)
    }
}

#Preview("Basic Layout") {
    GenerativeUIPreview(
        node: .vstack(spacing: 16, children: [
            .text("Hello, Generative UI!", font: "titleLarge"),
            .hstack(spacing: 8, children: [
                .button("Button 1"),
                .button("Button 2")
            ]),
            .spacer(),
            .text("Edit the JSON to see changes!", font: "caption", color: "textSecondary")
        ])
    )
    .padding()
}
