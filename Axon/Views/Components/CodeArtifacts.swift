//
//  CodeArtifacts.swift
//  Axon
//
//  ChatGPT/Claude-like code blocks + “artifact” expansion UI.
//

import SwiftUI
import Combine
import WebKit
import AxonArtifacts
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

// MARK: - Presenter (Environment)

#if os(macOS)
/// Available inspector tabs
enum InspectorTab: String, CaseIterable, Identifiable {
    case code = "Code"
    case bridgeLogs = "Bridge Logs"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .bridgeLogs: return "network"
        }
    }
}

/// Shared presenter so the inspector can live at the window/detail root level.
final class CodeArtifactPresenter: NSObject, ObservableObject {
    /// Currently selected artifact (explicitly clicked).
    @Published var selected: CodeArtifactPresentation? = nil

    /// Most recently presented artifact (fallback when nothing is selected).
    @Published var lastSeen: CodeArtifactPresentation? = nil

    /// Right inspector column open/closed.
    @Published var isOpen: Bool = false

    /// Width of the inspector (resizable).
    @Published var inspectorWidth: CGFloat = 480

    /// Currently active inspector tab.
    @Published var activeTab: InspectorTab = .code

    /// Minimum and maximum widths for resizing.
    static let minWidth: CGFloat = 320
    static let maxWidth: CGFloat = 800

    func present(_ presentation: CodeArtifactPresentation) {
        lastSeen = presentation
        selected = presentation
        activeTab = .code
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isOpen = true
        }
    }

    func present(_ artifact: CodeArtifact) {
        present(.single(artifact))
    }

    func present(workspace: ArtifactWorkspace, selectedPath: String? = nil) {
        present(.workspace(workspace, selectedPath: selectedPath))
    }

    func showBridgeLogs() {
        activeTab = .bridgeLogs
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            inspectorWidth = max(inspectorWidth, 720)
            isOpen = true
        }
    }

    func toggle() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isOpen.toggle()
        }
    }

    func close() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isOpen = false
        }
    }

    func clearSelection() {
        selected = nil
    }
}
#endif

private struct CodeArtifactPresenterKey: EnvironmentKey {
    static var defaultValue: ((CodeArtifactPresentation) -> Void)? = nil
}

extension EnvironmentValues {
    var presentCodeArtifact: ((CodeArtifactPresentation) -> Void)? {
        get { self[CodeArtifactPresenterKey.self] }
        set { self[CodeArtifactPresenterKey.self] = newValue }
    }
}

// MARK: - Shared Artifact Helpers

private enum CodeRenderability {
    static func normalizedLanguage(_ language: String?) -> String {
        resolvedLanguage(path: nil, language: language, code: "").id
    }

    static func isRenderable(_ language: String?) -> Bool {
        resolvedLanguage(path: nil, language: language, code: "").isRenderable
    }

    static func isJavaScriptCapable(_ language: String?) -> Bool {
        resolvedLanguage(path: nil, language: language, code: "").javaScriptCapable
    }

    static func resolvedLanguage(path: String?, language: String?, code: String) -> ResolvedLanguage {
        ArtifactEnvironmentLoader.shared
            .baseResolver()
            .resolveLanguage(path: path, explicitLanguage: language, content: code)
    }
}

private enum RenderableHTMLDocumentBuilder {
    static func document(from code: String, language: String?) -> String {
        let resolved = CodeRenderability.resolvedLanguage(path: nil, language: language, code: code)
        guard resolved.isRenderable else {
            return code
        }

        switch resolved.id {
        case "css":
            return """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <style>\(code)</style>
            </head>
            <body>
              <main id="app">
                <h1>CSS Preview</h1>
                <p>This scaffold lets you validate styles quickly.</p>
                <button>Button</button>
              </main>
            </body>
            </html>
            """
        case "javascript":
            return """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 24px; }
                #output { margin-top: 12px; padding: 12px; border: 1px solid #d0d0d0; border-radius: 8px; }
              </style>
            </head>
            <body>
              <h1>JavaScript Preview</h1>
              <div id="output">JS is running in this preview surface.</div>
              <script>\(code)</script>
            </body>
            </html>
            """
        default:
            return code
        }
    }
}

private struct ArtifactCodeContentView: View {
    let artifact: CodeArtifact
    let wrapLines: Bool

    var body: some View {
        Group {
            if wrapLines {
                ScrollView(.vertical) {
                    codeText
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ScrollView([.vertical, .horizontal]) {
                    codeText
                }
            }
        }
        .background(AppColors.substratePrimary)
    }

    private var codeText: some View {
        Text(artifact.code)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(AppColors.textPrimary)
            .textSelection(.enabled)
            .padding(16)
            .frame(maxWidth: wrapLines ? .infinity : nil, alignment: .leading)
    }
}

private struct ArtifactActionBar: View {
    let title: String
    let languageLabel: String
    let canPreview: Bool
    @Binding var wrapLines: Bool
    let copied: Bool
    let onCopy: () -> Void
    let onDownload: () -> Void
    let onPreview: () -> Void
    var onClose: (() -> Void)?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullLayout
            compactLayout
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColors.substratePrimary)
    }

    private var fullLayout: some View {
        HStack(spacing: 10) {
            if let onClose {
                closeButton(onClose)
            }

            Text(title)
                .font(AppTypography.titleSmall())
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            languageBadge
            wrapToggle

            if canPreview {
                actionButton(
                    title: "Preview",
                    icon: "play.rectangle",
                    action: onPreview
                )
            }

            actionButton(
                title: "Download",
                icon: "square.and.arrow.down",
                action: onDownload
            )

            actionButton(
                title: copied ? "Copied" : "Copy",
                icon: copied ? "checkmark" : "doc.on.doc",
                action: onCopy,
                tint: copied ? AppColors.signalLichen : AppColors.textSecondary
            )
        }
    }

    private var compactLayout: some View {
        HStack(spacing: 8) {
            if let onClose {
                closeButton(onClose)
            }

            Text(title)
                .font(AppTypography.titleSmall())
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            languageBadge

            if canPreview {
                iconButton(icon: "play.rectangle", tint: AppColors.textSecondary, action: onPreview)
            }

            Menu {
                Toggle("Wrap Lines", isOn: $wrapLines)

                if canPreview {
                    Button("Open Preview", action: onPreview)
                }

                Button(copied ? "Copied" : "Copy", action: onCopy)
                Button("Download", action: onDownload)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppColors.substrateSecondary)
                    )
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var wrapToggle: some View {
        Toggle("Wrap", isOn: $wrapLines)
            .toggleStyle(.switch)
            .font(AppTypography.labelSmall())
            .foregroundColor(AppColors.textSecondary)
    }

    private var languageBadge: some View {
        Text(languageLabel)
            .font(AppTypography.labelSmall())
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(AppColors.substrateSecondary)
            )
    }

    private func closeButton(_ onClose: @escaping () -> Void) -> some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.textSecondary)
                .padding(8)
                .background(Circle().fill(AppColors.substrateSecondary))
                .frame(minWidth: 32, minHeight: 32)
        }
        .buttonStyle(.plain)
    }

    private func actionButton(
        title: String,
        icon: String,
        action: @escaping () -> Void,
        tint: Color = AppColors.textSecondary
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(AppTypography.labelSmall())
                .foregroundColor(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColors.substrateSecondary)
                )
                .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
    }

    private func iconButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.substrateSecondary)
                )
        }
        .buttonStyle(.plain)
    }
}

#if os(macOS)
private func saveArtifactOnMacOS(_ artifact: CodeArtifact) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = artifact.exportFileURL.lastPathComponent
    if let type = UTType(filenameExtension: artifact.fileExtension) {
        panel.allowedContentTypes = [type]
    } else {
        panel.allowedContentTypes = [.plainText]
    }
    panel.canCreateDirectories = true

    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        do {
            try artifact.code.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("[CodeArtifact] Failed to save file: \(error)")
        }
    }
}
#endif

private final class PreviewNavigationDelegate: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame != true else {
            decisionHandler(.allow)
            return
        }

        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            decisionHandler(.cancel)
            return
        }

        if navigationAction.navigationType == .linkActivated,
           navigationAction.request.url?.isFileURL != true {
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}

private struct ArtifactWebPreview: View {
    let html: String
    let javaScriptEnabled: Bool

    var body: some View {
        ArtifactWebPreviewRepresentable(
            html: html,
            javaScriptEnabled: javaScriptEnabled
        )
        .background(AppColors.substratePrimary)
    }
}

#if os(iOS)
private struct ArtifactWebPreviewRepresentable: UIViewRepresentable {
    let html: String
    let javaScriptEnabled: Bool

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = javaScriptEnabled
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.configuration.preferences.javaScriptEnabled = javaScriptEnabled
        uiView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> PreviewNavigationDelegate {
        PreviewNavigationDelegate()
    }
}
#elseif os(macOS)
private struct ArtifactWebPreviewRepresentable: NSViewRepresentable {
    let html: String
    let javaScriptEnabled: Bool

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = javaScriptEnabled
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.configuration.preferences.javaScriptEnabled = javaScriptEnabled
        nsView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> PreviewNavigationDelegate {
        PreviewNavigationDelegate()
    }
}
#endif

private struct RenderedCodePreviewSheet: View {
    let artifact: CodeArtifact
    @Binding var javaScriptEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Rendered Preview")
                    .font(AppTypography.titleSmall())
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                if jsCapable {
                    Toggle("JS", isOn: $javaScriptEnabled)
                        .toggleStyle(.switch)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                }

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.substrateSecondary)
                )
            }
            .padding(12)
            .background(AppColors.substratePrimary)

            Divider().overlay(AppColors.glassBorder.opacity(0.6))

            ArtifactWebPreview(
                html: previewDocument,
                javaScriptEnabled: javaScriptEnabled && jsCapable
            )
        }
        .background(AppColors.substratePrimary)
    }

    private var jsCapable: Bool {
        CodeRenderability.isJavaScriptCapable(artifact.language)
    }

    private var previewDocument: String {
        RenderableHTMLDocumentBuilder.document(from: artifact.code, language: artifact.language)
    }
}

// MARK: - Artifact View

struct CodeArtifactView: View {
    let artifact: CodeArtifact

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var showExportSheet = false
    @State private var wrapLines = true
    @State private var showRenderedPreview = false
    @State private var previewJavaScriptEnabled = false

    private var languageLabel: String {
        let raw = artifact.language?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false ? raw! : "code")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(AppColors.glassBorder.opacity(0.6))

            ArtifactCodeContentView(artifact: artifact, wrapLines: wrapLines)
        }
        .background(AppColors.substratePrimary)
        .sheet(isPresented: $showExportSheet) {
            #if canImport(UIKit)
            ActivityView(activityItems: [artifact.exportFileURL])
            #else
            EmptyView()
            #endif
        }
        .sheet(isPresented: $showRenderedPreview) {
            RenderedCodePreviewSheet(
                artifact: artifact,
                javaScriptEnabled: $previewJavaScriptEnabled
            )
        }
    }

    private var header: some View {
        ArtifactActionBar(
            title: artifact.title.isEmpty ? "Code" : artifact.title,
            languageLabel: languageLabel,
            canPreview: CodeRenderability.isRenderable(artifact.language),
            wrapLines: $wrapLines,
            copied: copied,
            onCopy: copyCode,
            onDownload: saveOrExportArtifact,
            onPreview: { showRenderedPreview = true },
            onClose: { dismiss() }
        )
    }

    private func saveOrExportArtifact() {
        #if os(macOS)
        saveArtifactOnMacOS(artifact)
        #else
        showExportSheet = true
        #endif
    }

    private func copyCode() {
        AppClipboard.copy(artifact.code)
        withAnimation(.easeInOut(duration: 0.15)) {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.15)) {
                copied = false
            }
        }
    }
}

// MARK: - Code Block View (inline)

struct CodeBlockView<Content: View>: View {
    let language: String?
    let filePath: String?
    let workspace: ArtifactWorkspace?
    let code: String
    /// Optional extra content injected from the call site.
    /// When nil (use the `EmptyView` convenience init), `CodeBlockView` renders the code text itself.
    let content: Content?

    /// When true the block is being actively streamed — shows a loading pulse and starts collapsed.
    var isStreaming: Bool = false

    /// Full init with a custom content closure.
    init(
        language: String? = nil,
        filePath: String? = nil,
        workspace: ArtifactWorkspace? = nil,
        code: String,
        isStreaming: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.language = language
        self.filePath = filePath
        self.workspace = workspace
        self.code = code
        self.isStreaming = isStreaming
        self.content = content()
    }

    @Environment(\.presentCodeArtifact) private var presentArtifact
    @State private var copied = false
    @State private var isCollapsed = true   // always start collapsed
    @State private var wrapLines = false
    /// Drives the rightward shimmer animation when isStreaming == true.
    @State private var shimmerOffset: CGFloat = -1.0

    private var languageLabel: String {
        let raw = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false ? raw! : "code")
    }

    private var displayLabel: String {
        let path = filePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? languageLabel : path
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if !isCollapsed {
                codeBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AppColors.substrateTertiary)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isCollapsed)
        // Auto-collapse when the block scrolls out of view (top edge above screen).
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: CodeBlockFramePreferenceKey.self,
                        value: geo.frame(in: .global).minY
                    )
            }
        )
        .onPreferenceChange(CodeBlockFramePreferenceKey.self) { minY in
            // Collapse when the top of the block has scrolled more than 60 pts above the screen top.
            if minY < -60 && !isCollapsed {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isCollapsed = true
                }
            }
        }
        .onAppear {
            if isStreaming {
                startShimmer()
            }
        }
        .onChange(of: isStreaming) { _, streaming in
            if streaming {
                startShimmer()
            }
        }
    }

    // MARK: - Shimmer

    private func startShimmer() {
        shimmerOffset = -1.0
        withAnimation(
            .linear(duration: 1.2)
            .repeatForever(autoreverses: false)
        ) {
            shimmerOffset = 2.0
        }
    }

    // MARK: - Code Body

    @ViewBuilder
    private var codeBody: some View {
        if wrapLines {
            ScrollView(.vertical, showsIndicators: true) {
                codeText
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(AppColors.substrateTertiary)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                codeText
                    .padding(12)
            }
            .background(AppColors.substrateTertiary)
        }
    }

    private var codeText: some View {
        // Prefer injected content; fall back to self-rendered caption-size monospaced text.
        Group {
            if let content {
                content
            } else {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(AppColors.textPrimary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            // Collapse / expand chevron
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isCollapsed.toggle()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isCollapsed)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .help(isCollapsed ? "Expand" : "Collapse")
            #endif

            if isStreaming {
                // Streaming loading badge — label + rightward green shimmer pulse
                streamingBadge
            } else {
                Text(displayLabel)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(AppColors.substrateSecondary)
                    )
            }

            Spacer()

            if !isStreaming {
                // Wrap lines toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        wrapLines.toggle()
                    }
                } label: {
                    Image(systemName: wrapLines ? "arrow.down.left.and.arrow.up.right" : "arrow.left.and.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(wrapLines ? AppColors.signalMercury : AppColors.textSecondary)
                        .padding(7)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(wrapLines ? AppColors.signalMercury.opacity(0.15) : AppColors.substrateSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppColors.glassBorder.opacity(0.7), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .help(wrapLines ? "Disable line wrapping" : "Enable line wrapping")
                #endif

                // Send to Inspector button
                Button {
                    if let workspace {
                        presentArtifact?(.workspace(workspace, selectedPath: filePath))
                    } else {
                        let artifact = CodeArtifact(
                            title: "Code",
                            language: language,
                            code: code
                        )
                        presentArtifact?(.single(artifact))
                    }
                } label: {
                    Image(systemName: "apple.terminal.on.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .padding(7)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppColors.substrateSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppColors.glassBorder.opacity(0.7), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .help("Open in Inspector")
                #endif

                Button {
                    AppClipboard.copy(code)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        copied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            copied = false
                        }
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(copied ? AppColors.signalLichen : AppColors.textSecondary)
                        .padding(7)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppColors.substrateSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppColors.glassBorder.opacity(0.7), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.substrateElevated.opacity(0.55))
        .overlay(
            Rectangle()
                .fill(AppColors.glassBorder.opacity(0.7))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Streaming Badge

    /// A capsule badge with the language label and a rightward green shimmer pulse.
    private var streamingBadge: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Base capsule
                Capsule()
                    .fill(AppColors.substrateSecondary)

                // Shimmer overlay — a narrow green gradient that sweeps right
                let shimmerWidth = geo.size.width * 0.55
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        AppColors.signalLichen.opacity(0.55),
                        Color.clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: shimmerWidth)
                .offset(x: shimmerOffset * geo.size.width)
                .clipShape(Capsule())
            }
            .overlay(
                Text(displayLabel.isEmpty ? "code" : displayLabel)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.signalLichen.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            )
        }
        .frame(height: 26)
        .fixedSize(horizontal: true, vertical: false)
        // Ensure the GeometryReader has a sensible minimum width
        .frame(minWidth: 60)
    }
}

/// Convenience init — lets callers skip the content closure; the block renders the code itself.
extension CodeBlockView where Content == EmptyView {
    init(
        language: String? = nil,
        filePath: String? = nil,
        workspace: ArtifactWorkspace? = nil,
        code: String,
        isStreaming: Bool = false
    ) {
        self.language = language
        self.filePath = filePath
        self.workspace = workspace
        self.code = code
        self.isStreaming = isStreaming
        self.content = nil
    }
}

// MARK: - Preference Key for auto-collapse on scroll

private struct CodeBlockFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CodeArtifactPresentationSheetView: View {
    let presentation: CodeArtifactPresentation

    var body: some View {
        switch presentation {
        case .single(let artifact):
            CodeArtifactView(artifact: artifact)
        case .workspace(let workspace, let selectedPath):
            ArtifactWorkspaceEditorView(
                initialWorkspace: workspace,
                initialSelectedPath: selectedPath,
                context: .chatSnapshot,
                onWorkspaceUpdated: nil
            )
        }
    }
}

private enum WorkspaceEditorTab: String, CaseIterable, Identifiable {
    case code = "Code"
    case preview = "Preview"

    var id: String { rawValue }
}

private enum WorkspacePathPromptKind: String, Identifiable {
    case newFile
    case newFolder
    case renameFile
    case renameFolder

    var id: String { rawValue }
}

// MARK: - Sidebar width preference key

/// Bubbles up the natural (unwrapped) width of each sidebar label so we can
/// compute the minimum sidebar width from the longest filename.
private struct SidebarLabelWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ArtifactWorkspaceEditorView: View {
    let context: ArtifactWorkspaceEditorContext
    let onWorkspaceUpdated: ((ArtifactWorkspace) -> Void)?

    @State private var workspace: ArtifactWorkspace
    @State private var selectedFilePath: String?
    @State private var selectedTab: WorkspaceEditorTab = .code
    @State private var javaScriptEnabled: Bool = true
    @State private var collapsedFolders: Set<String> = []
    @State private var promptKind: WorkspacePathPromptKind?
    @State private var promptText = ""
    @State private var renameSourcePath: String?
    @State private var pendingDeletePath: String?
    @State private var pendingDeleteIsFolder = false
    @State private var forkCreatedToast = false

    // Sidebar resize / visibility
    @State private var isSidebarVisible: Bool = true
    @State private var sidebarWidth: CGFloat = 200
    @State private var isDraggingSidebar: Bool = false
    /// Dynamically computed from the widest filename label; updated via PreferenceKey.
    @State private var computedSidebarMinWidth: CGFloat = 120

    private static let sidebarAbsoluteMin: CGFloat = 100
    private static let sidebarMaxWidth: CGFloat = 400
    /// Extra space beyond the text: icon (11pt) + icon gap (6) + leading indent base (18+6) + outer padding (10+10) + drag handle (1) ≈ 62
    private static let sidebarLabelPadding: CGFloat = 62

    init(
        initialWorkspace: ArtifactWorkspace,
        initialSelectedPath: String?,
        context: ArtifactWorkspaceEditorContext,
        onWorkspaceUpdated: ((ArtifactWorkspace) -> Void)?
    ) {
        self.context = context
        self.onWorkspaceUpdated = onWorkspaceUpdated

        _workspace = State(initialValue: initialWorkspace)
        let initialFile = initialSelectedPath
            ?? initialWorkspace.entryPath
            ?? initialWorkspace.files.first?.path
        _selectedFilePath = State(initialValue: initialFile)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Divider().overlay(AppColors.glassBorder.opacity(0.5))

            HStack(spacing: 0) {
                if isSidebarVisible {
                    sidebar
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    Divider().overlay(AppColors.glassBorder.opacity(0.5))
                }

                mainPane
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSidebarVisible)
        }
        .background(AppColors.substratePrimary)
        .alert(
            promptTitle,
            isPresented: Binding(
                get: { promptKind != nil },
                set: { if !$0 { promptKind = nil } }
            )
        ) {
            TextField(promptPlaceholder, text: $promptText)
            Button("Cancel", role: .cancel) {
                promptKind = nil
                promptText = ""
                renameSourcePath = nil
            }
            Button("Apply") {
                applyPromptAction()
            }
        } message: {
            Text(promptMessage)
        }
        .alert(
            "Delete \(pendingDeleteIsFolder ? "Folder" : "File")",
            isPresented: Binding(
                get: { pendingDeletePath != nil },
                set: { if !$0 { pendingDeletePath = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingDeletePath = nil
            }
            Button("Delete", role: .destructive) {
                guard let path = pendingDeletePath else { return }
                guard ensureEditable() else { return }
                workspace.removePath(path)
                if selectedFilePath == path || (selectedFilePath?.hasPrefix("\(path)/") == true) {
                    selectedFilePath = workspace.entryPath ?? workspace.files.first?.path
                }
                persistWorkspace()
                pendingDeletePath = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .overlay(alignment: .topTrailing) {
            if forkCreatedToast {
                Text("Created editable fork")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.signalLichen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(AppColors.signalLichen.opacity(0.15))
                    )
                    .padding()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            // ── Row 1: Identity ──────────────────────────────────────────
            HStack(spacing: 8) {
                // Sidebar toggle
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSidebarVisible ? AppColors.signalMercury : AppColors.textSecondary)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSidebarVisible
                                      ? AppColors.signalMercury.opacity(0.15)
                                      : AppColors.substrateSecondary)
                        )
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
                #endif

                Text(workspace.title)
                    .font(AppTypography.titleSmall())
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if workspace.isReadOnlySnapshot {
                    Text("Snapshot")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppColors.substrateSecondary))
                } else if workspace.isEditableFork {
                    Text("Editable Fork")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalLichen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppColors.signalLichen.opacity(0.12)))
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // ── Row 2: Controls ──────────────────────────────────────────
            HStack(spacing: 8) {
                Picker("", selection: $selectedTab) {
                    ForEach(WorkspaceEditorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                if selectedTab == .preview {
                    Toggle("JS", isOn: $javaScriptEnabled)
                        .toggleStyle(.switch)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .animation(.easeInOut(duration: 0.15), value: selectedTab)
        }
        .background(AppColors.substratePrimary)
    }

    private var sidebar: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Button {
                        promptKind = .newFile
                        promptText = "index.html"
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .help("New File")
                    #endif

                    Button {
                        promptKind = .newFolder
                        promptText = "src"
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .help("New Folder")
                    #endif

                    Spacer()
                }
                .foregroundColor(AppColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Divider().overlay(AppColors.glassBorder.opacity(0.4))

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(workspace.fileTree) { node in
                            workspaceNodeRow(node: node, depth: 0)
                        }
                    }
                    .padding(8)
                }
                .background(AppColors.substrateSecondary.opacity(0.35))
                // Collect the widest label width from all sidebar rows
                .onPreferenceChange(SidebarLabelWidthKey.self) { maxLabelWidth in
                    let needed = maxLabelWidth + ArtifactWorkspaceEditorView.sidebarLabelPadding
                    let clamped = min(
                        ArtifactWorkspaceEditorView.sidebarMaxWidth,
                        max(ArtifactWorkspaceEditorView.sidebarAbsoluteMin, needed)
                    )
                    if clamped != computedSidebarMinWidth {
                        computedSidebarMinWidth = clamped
                        // Snap current width up if it's now below the new minimum
                        if sidebarWidth < clamped {
                            sidebarWidth = clamped
                        }
                    }
                }
            }
            .frame(width: sidebarWidth)
            .background(AppColors.substratePrimary)

            // Drag handle on the right edge of the sidebar
            Rectangle()
                .fill(isDraggingSidebar ? AppColors.signalMercury.opacity(0.3) : AppColors.glassBorder.opacity(0.7))
                .frame(width: isDraggingSidebar ? 3 : 1)
                .contentShape(Rectangle().inset(by: -4))
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            isDraggingSidebar = true
                            let newWidth = sidebarWidth + value.translation.width
                            sidebarWidth = min(
                                ArtifactWorkspaceEditorView.sidebarMaxWidth,
                                max(computedSidebarMinWidth, newWidth)
                            )
                        }
                        .onEnded { _ in
                            isDraggingSidebar = false
                        }
                )
                #if os(macOS)
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                #endif
        }
    }

    private func workspaceNodeRow(node: ArtifactWorkspaceNode, depth: Int) -> AnyView {
        switch node {
        case .folder(let name, let path, let children):
            let isCollapsed = collapsedFolders.contains(path)
            return AnyView(
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Button {
                            if isCollapsed {
                                collapsedFolders.remove(path)
                            } else {
                                collapsedFolders.insert(path)
                            }
                        } label: {
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .buttonStyle(.plain)

                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.signalMercury)

                        Text(name)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                            // Report this label's natural width upward
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: SidebarLabelWidthKey.self,
                                        value: geo.size.width
                                    )
                                }
                            )

                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 12)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("New File in Folder") {
                            promptKind = .newFile
                            promptText = "\(path)/new_file.txt"
                        }
                        Button("Rename Folder") {
                            promptKind = .renameFolder
                            renameSourcePath = path
                            promptText = path
                        }
                        Button("Delete Folder", role: .destructive) {
                            pendingDeletePath = path
                            pendingDeleteIsFolder = true
                        }
                    }

                    if !isCollapsed {
                        ForEach(children) { child in
                            workspaceNodeRow(node: child, depth: depth + 1)
                        }
                    }
                }
            )

        case .file(let file):
            if file.filename != ".keep" {
                let selected = selectedFilePath == file.path
                return AnyView(
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundColor(selected ? AppColors.signalMercury : AppColors.textTertiary)

                        Text(file.filename)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(selected ? AppColors.signalMercury : AppColors.textPrimary)
                            .lineLimit(1)
                            // Report this label's natural width upward
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: SidebarLabelWidthKey.self,
                                        value: geo.size.width
                                    )
                                }
                            )

                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 12 + 18)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? AppColors.signalMercury.opacity(0.15) : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        selectedFilePath = file.path
                        selectedTab = .code
                    }
                    .contextMenu {
                        Button("Set as Entrypoint") {
                            guard ensureEditable() else { return }
                            workspace.setEntrypoint(file.path)
                            persistWorkspace()
                        }
                        Button("Rename File") {
                            promptKind = .renameFile
                            renameSourcePath = file.path
                            promptText = file.path
                        }
                        Button("Delete File", role: .destructive) {
                            pendingDeletePath = file.path
                            pendingDeleteIsFolder = false
                        }
                    }
                )
            }
            return AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private var mainPane: some View {
        if selectedTab == .preview {
            ArtifactWorkspacePreviewPane(
                workspace: workspace,
                javaScriptEnabled: javaScriptEnabled
            )
        } else if let file = selectedFile {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(file.path)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    Text(file.inferredLanguage.uppercased())
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppColors.substrateSecondary))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.substratePrimary)

                Divider().overlay(AppColors.glassBorder.opacity(0.4))

                TextEditor(
                    text: Binding(
                        get: { selectedFile?.content ?? "" },
                        set: { newValue in
                            guard let path = selectedFilePath else { return }
                            guard ensureEditable() else { return }
                            workspace.updateFileContent(path: path, content: newValue)
                            persistWorkspace()
                        }
                    )
                )
                .font(.system(size: 13, design: .monospaced))
                .padding(8)
                .background(AppColors.substratePrimary)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 28))
                    .foregroundColor(AppColors.textTertiary)
                Text("Select a file")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.substratePrimary)
        }
    }

    private var selectedFile: ArtifactWorkspaceFile? {
        guard let path = selectedFilePath else { return nil }
        return workspace.file(at: path)
    }

    private var promptTitle: String {
        switch promptKind {
        case .newFile: return "Create File"
        case .newFolder: return "Create Folder"
        case .renameFile: return "Rename File"
        case .renameFolder: return "Rename Folder"
        case .none: return ""
        }
    }

    private var promptPlaceholder: String {
        switch promptKind {
        case .newFile: return "src/index.html"
        case .newFolder: return "src/components"
        case .renameFile: return "new/name.txt"
        case .renameFolder: return "new/folder/name"
        case .none: return ""
        }
    }

    private var promptMessage: String {
        switch promptKind {
        case .newFile:
            return "Enter a relative file path."
        case .newFolder:
            return "Folder paths are virtual; files under this path will appear grouped."
        case .renameFile, .renameFolder:
            return "Enter the new relative path."
        case .none:
            return ""
        }
    }

    private func applyPromptAction() {
        guard let promptKind else { return }
        defer {
            self.promptKind = nil
            self.promptText = ""
            self.renameSourcePath = nil
        }

        switch promptKind {
        case .newFile:
            guard ensureEditable() else { return }
            guard let normalized = ArtifactWorkspace.normalizeRelativePath(promptText) else { return }
            workspace.upsertFile(path: normalized, content: defaultFileContent(for: normalized))
            selectedFilePath = normalized
            persistWorkspace()
        case .newFolder:
            guard ensureEditable() else { return }
            // Virtual folder support: create placeholder .keep file when empty.
            guard let normalized = ArtifactWorkspace.normalizeRelativePath(promptText) else { return }
            let keep = "\(normalized)/.keep"
            workspace.upsertFile(path: keep, content: "")
            if collapsedFolders.contains(normalized) {
                collapsedFolders.remove(normalized)
            }
            selectedFilePath = workspace.entryPath ?? workspace.files.first(where: { $0.filename != ".keep" })?.path
            persistWorkspace()
        case .renameFile, .renameFolder:
            guard ensureEditable() else { return }
            guard let from = renameSourcePath,
                  let normalized = ArtifactWorkspace.normalizeRelativePath(promptText) else { return }
            workspace.renamePath(from: from, to: normalized)
            if let selected = selectedFilePath {
                if selected == from {
                    selectedFilePath = normalized
                } else {
                    let prefix = from.hasSuffix("/") ? from : "\(from)/"
                    if selected.hasPrefix(prefix) {
                        let suffix = String(selected.dropFirst(prefix.count))
                        selectedFilePath = "\(normalized)/\(suffix)"
                    }
                }
            }
            persistWorkspace()
        }
    }

    private func defaultFileContent(for path: String) -> String {
        let language = CodeRenderability
            .resolvedLanguage(path: path, language: nil, code: "")
            .id

        switch language {
        case "html":
            return """
            <!doctype html>
            <html lang=\"en\">
            <head>
              <meta charset=\"utf-8\">
              <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
              <title>Artifact Preview</title>
            </head>
            <body>
              <h1>Hello from \(path)</h1>
            </body>
            </html>
            """
        case "css":
            return "body {\n  font-family: -apple-system, BlinkMacSystemFont, sans-serif;\n}\n"
        case "javascript":
            return "console.log('hello from \(path)');\n"
        default:
            return ""
        }
    }

    private func ensureEditable() -> Bool {
        guard workspace.isReadOnlySnapshot else { return true }
        switch context {
        case .chatSnapshot, .gallery:
            break
        }
        guard let fork = CreativeGalleryService.shared.createEditableForkWorkspace(from: workspace) else {
            return false
        }
        workspace = fork
        withAnimation(.easeInOut(duration: 0.18)) {
            forkCreatedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.18)) {
                forkCreatedToast = false
            }
        }
        onWorkspaceUpdated?(workspace)
        return true
    }

    private func persistWorkspace() {
        workspace.updatedAt = Date()
        if workspace.isEditableFork {
            CreativeGalleryService.shared.saveWorkspaceFork(workspace)
        }
        onWorkspaceUpdated?(workspace)
    }
}

private struct ArtifactWorkspacePreviewPane: View {
    let workspace: ArtifactWorkspace
    let javaScriptEnabled: Bool

    @State private var rootURL: URL?
    @State private var entryURL: URL?
    @State private var refreshToken = UUID()

    var body: some View {
        Group {
            if let rootURL, let entryURL {
                ArtifactWorkspaceWebPreviewRepresentable(
                    rootURL: rootURL,
                    entryURL: entryURL,
                    javaScriptEnabled: javaScriptEnabled
                )
                .id(refreshToken)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 28))
                        .foregroundColor(AppColors.textTertiary)
                    Text("No renderable preview")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppColors.substratePrimary)
        .onAppear(perform: rebuildPreview)
        .onChange(of: workspace) { _, _ in
            rebuildPreview()
        }
        .onChange(of: javaScriptEnabled) { _, _ in
            refreshToken = UUID()
        }
    }

    private func rebuildPreview() {
        if let preview = ArtifactWorkspacePreviewBuilder.materialize(workspace: workspace) {
            rootURL = preview.rootURL
            entryURL = preview.entryURL
            refreshToken = UUID()
        } else {
            rootURL = nil
            entryURL = nil
        }
    }
}

#if os(iOS)
private struct ArtifactWorkspaceWebPreviewRepresentable: UIViewRepresentable {
    let rootURL: URL
    let entryURL: URL
    let javaScriptEnabled: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = javaScriptEnabled
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.configuration.preferences.javaScriptEnabled = javaScriptEnabled
        uiView.loadFileURL(entryURL, allowingReadAccessTo: rootURL)
    }

    func makeCoordinator() -> PreviewNavigationDelegate {
        PreviewNavigationDelegate()
    }
}
#elseif os(macOS)
private struct ArtifactWorkspaceWebPreviewRepresentable: NSViewRepresentable {
    let rootURL: URL
    let entryURL: URL
    let javaScriptEnabled: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = javaScriptEnabled
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.configuration.preferences.javaScriptEnabled = javaScriptEnabled
        nsView.loadFileURL(entryURL, allowingReadAccessTo: rootURL)
    }

    func makeCoordinator() -> PreviewNavigationDelegate {
        PreviewNavigationDelegate()
    }
}
#endif

private enum ArtifactWorkspacePreviewBuilder {
    static func materialize(workspace: ArtifactWorkspace) -> (rootURL: URL, entryURL: URL)? {
        let fm = FileManager.default
        let resolver = ArtifactEnvironmentLoader.shared.resolver(for: workspace)
        let previewPlan = resolver.resolvePreviewPlan(workspace: workspace)

        guard previewPlan.strategy != .none else {
            return nil
        }

        let root = fm.temporaryDirectory
            .appendingPathComponent("axon-artifact-preview")
            .appendingPathComponent(workspace.id, isDirectory: true)

        do {
            if fm.fileExists(atPath: root.path) {
                try fm.removeItem(at: root)
            }
            try fm.createDirectory(at: root, withIntermediateDirectories: true)

            var htmlPaths = Set<String>()
            var cssContent: [String] = []
            var jsContent: [String] = []

            for file in workspace.files {
                guard let normalized = ArtifactWorkspace.normalizeRelativePath(file.path) else { continue }
                let targetURL = root.appendingPathComponent(normalized)
                try fm.createDirectory(
                    at: targetURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try file.content.data(using: .utf8)?.write(to: targetURL, options: [.atomic])

                let resolved = resolver.resolveLanguage(
                    path: normalized,
                    explicitLanguage: file.language,
                    content: file.content
                )

                if resolved.id == "html" {
                    htmlPaths.insert(normalized)
                }
                if resolved.id == "css" {
                    cssContent.append(file.content)
                } else if resolved.id == "javascript" {
                    jsContent.append(file.content)
                }
            }

            if previewPlan.strategy == .webEntry,
               let entryPath = previewPlan.entryPath,
               htmlPaths.contains(entryPath) {
                return (root, root.appendingPathComponent(entryPath))
            }

            guard previewPlan.strategy == .webFallback || !cssContent.isEmpty || !jsContent.isEmpty else {
                return nil
            }

            let fallbackURL = root.appendingPathComponent("__fallback_preview__.html")
            let fallback = """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>\(workspace.title)</title>
              <style>\(cssContent.joined(separator: "\n\n"))</style>
            </head>
            <body>
              <main id="app">
                <h1>\(workspace.title)</h1>
                <p>No HTML entrypoint was found, so this fallback was generated.</p>
              </main>
              <script>\(jsContent.joined(separator: "\n\n"))</script>
            </body>
            </html>
            """
            try fallback.write(to: fallbackURL, atomically: true, encoding: .utf8)
            return (root, fallbackURL)
        } catch {
            return nil
        }
    }
}

// MARK: - Host modifier

/// iOS uses sheet-based presentation; macOS relies on the inspector set higher up.
struct CodeArtifactHost: ViewModifier {
    @State private var selected: CodeArtifactPresentation? = nil

    func body(content: Content) -> some View {
        #if os(macOS)
        // On macOS, don't override the environment - let the inspector's
        // environment value from MacDetailWithInspector flow through.
        content
        #else
        content
            .environment(\.presentCodeArtifact, { artifact in
                selected = artifact
            })
            .sheet(item: $selected) { presentation in
                CodeArtifactPresentationSheetView(presentation: presentation)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        #endif
    }
}

extension View {
    func codeArtifactHost() -> some View {
        modifier(CodeArtifactHost())
    }
}

#if os(macOS)
struct CodeArtifactInspectorColumn: View {
    @ObservedObject var presenter: CodeArtifactPresenter

    @State private var isDragging = false
    @State private var wrapLines = true
    @State private var showRenderedPreview = false
    @State private var previewJavaScriptEnabled = false
    @State private var copied = false

    private var artifactToShow: CodeArtifactPresentation? {
        presenter.selected ?? presenter.lastSeen
    }

    var body: some View {
        HStack(spacing: 0) {
            // Resize handle on the left edge
            resizeHandle

            VStack(spacing: 0) {
                // Header bar
                header

                Divider()
                    .overlay(AppColors.glassBorder.opacity(0.6))

                // Tab content
                switch presenter.activeTab {
                case .code:
                    if let artifact = artifactToShow {
                        inspectorArtifactView(artifact: artifact)
                    } else {
                        emptyState
                    }
                case .bridgeLogs:
                    BridgeLogInspector(availableWidth: presenter.inspectorWidth)
                }
            }
        }
        .frame(width: presenter.inspectorWidth)
        .frame(maxHeight: .infinity)
        .background(AppColors.substratePrimary)
        .sheet(isPresented: $showRenderedPreview) {
            if case .single(let artifact) = artifactToShow {
                RenderedCodePreviewSheet(
                    artifact: artifact,
                    javaScriptEnabled: $previewJavaScriptEnabled
                )
                .frame(minWidth: 760, minHeight: 540)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Close button
                Button {
                    presenter.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .padding(6)
                        .background(
                            Circle().fill(AppColors.substrateSecondary)
                        )
                }
                .buttonStyle(.plain)
                .help("Close Inspector")

                Text("Inspector")
                    .font(AppTypography.titleSmall())
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                if presenter.activeTab == .code && presenter.selected != nil {
                    Button("Clear") {
                        presenter.clearSelection()
                    }
                    .buttonStyle(.plain)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Tab bar
            HStack(spacing: 0) {
                ForEach(InspectorTab.allCases) { tab in
                    InspectorTabButton(
                        tab: tab,
                        isSelected: presenter.activeTab == tab,
                        action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                presenter.activeTab = tab
                                if tab == .bridgeLogs {
                                    presenter.inspectorWidth = max(presenter.inspectorWidth, 720)
                                }
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(AppColors.substratePrimary)
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(isDragging ? AppColors.signalMercury.opacity(0.3) : AppColors.glassBorder.opacity(0.7))
            .frame(width: isDragging ? 3 : 1)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        // Dragging left (negative) increases width, right (positive) decreases
                        let newWidth = presenter.inspectorWidth - value.translation.width
                        presenter.inspectorWidth = min(
                            CodeArtifactPresenter.maxWidth,
                            max(CodeArtifactPresenter.minWidth, newWidth)
                        )
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    @ViewBuilder
    private func inspectorArtifactView(artifact: CodeArtifactPresentation) -> some View {
        switch artifact {
        case .single(let single):
            VStack(spacing: 0) {
                let lang = single.language?.trimmingCharacters(in: .whitespacesAndNewlines)
                ArtifactActionBar(
                    title: single.title.isEmpty ? "Code" : single.title,
                    languageLabel: (lang?.isEmpty == false ? lang! : "code"),
                    canPreview: CodeRenderability.isRenderable(single.language),
                    wrapLines: $wrapLines,
                    copied: copied,
                    onCopy: { copyCode(single.code) },
                    onDownload: { saveArtifactOnMacOS(single) },
                    onPreview: { showRenderedPreview = true },
                    onClose: nil
                )
                .background(AppColors.substrateElevated.opacity(0.3))

                Divider()
                    .overlay(AppColors.glassBorder.opacity(0.4))

                ArtifactCodeContentView(artifact: single, wrapLines: wrapLines)
            }
        case .workspace(let workspace, let selectedPath):
            ArtifactWorkspaceEditorView(
                initialWorkspace: workspace,
                initialSelectedPath: selectedPath,
                context: .chatSnapshot,
                onWorkspaceUpdated: nil
            )
        }
    }

    private func copyCode(_ code: String) {
        AppClipboard.copy(code)
        withAnimation(.easeInOut(duration: 0.15)) {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.15)) {
                copied = false
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No code yet")
                .font(AppTypography.titleSmall())
                .foregroundColor(AppColors.textPrimary)

            Text("When an assistant message includes a code block, click it and it will appear here. Axon will also keep the most recent snippet around.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.substratePrimary)
    }
}

private struct InspectorTabButton: View {
    let tab: InspectorTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12))
                Text(tab.rawValue)
                    .font(AppTypography.labelSmall())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.2) : Color.clear)
            )
            .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
        }
        .buttonStyle(.plain)
    }
}
#endif

// MARK: - Completed Tool Call View

/// Displays an already-executed tool call from persisted message data.
/// This prevents re-execution of tools when messages are reloaded from storage.
struct CompletedToolCallView: View {
    let toolCall: LiveToolCall

    @State private var isExpanded: Bool = false

    private var stateColor: Color {
        switch toolCall.state {
        case .success: return AppColors.signalLichen
        case .failure: return AppColors.signalHematite
        case .running: return AppColors.signalMercury
        case .pending: return AppColors.textTertiary
        }
    }

    private var borderColor: Color {
        switch toolCall.state {
        case .success: return AppColors.signalLichen
        case .failure: return AppColors.signalHematite
        default: return AppColors.glassBorder
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                expandedContent
            }
        }
        .background(AppColors.substrateTertiary)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(spacing: 10) {
            // Tool icon and name
            Image(systemName: toolCall.icon)
                .font(.system(size: 14))
                .foregroundColor(stateColor)

            Text(toolCall.displayName)
                .font(AppTypography.bodySmall(.medium))
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            // State indicator
            HStack(spacing: 6) {
                Image(systemName: toolCall.state == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(stateColor)

                if let duration = toolCall.duration {
                    Text(String(format: "%.1fs", duration))
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }

                // Expand/collapse chevron
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(stateColor.opacity(0.1))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3)) {
                isExpanded.toggle()
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Query
            if let query = toolCall.request?.query {
                Text(query)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(3)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            // Result if available
            if let result = toolCall.result {
                Divider()
                    .overlay(AppColors.glassBorder.opacity(0.5))

                Text(result.output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(result.success ? AppColors.textSecondary : AppColors.signalHematite)
                    .lineLimit(5)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .padding(.bottom, toolCall.result == nil ? 8 : 0)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Tool Request Code Block View

/// Specialized code block for tool_request that auto-executes on appear
/// The tool request stays in the markdown content but is rendered as a minimal/hidden UI
/// This decouples display from execution - we can parse and execute at leisure after streaming completes
struct ToolRequestCodeBlockView: View {
    let code: String

    /// When true, this tool request was loaded from conversation history (not newly streamed)
    /// Tools from history should NOT auto-execute - they should only show their persisted state
    var isFromHistory: Bool = false

    /// Controls whether tool requests auto-execute when they appear
    /// Reads from global tool settings - .immediate = auto-execute, .deferred = manual apply
    private var autoExecuteEnabled: Bool {
        SettingsViewModel.shared.settings.toolSettings.executionMode == .immediate
    }

    @State private var executionState: ToolExecutionState = .notExecuted
    @State private var executionResult: String?
    @State private var isExpanded: Bool = false
    @State private var assertionOutcome: ToolTestAssertionOutcome = .unavailable
    @State private var executionDurationMs: Int?

    private enum ToolExecutionState {
        case notExecuted
        case executing
        case success
        case failure
    }

    private var requestParseResult: ToolRequestParseResult {
        ToolTestRequestParser.parse(code)
    }

    private var parsedRequest: ParsedToolRequestWithMetadata? {
        if case .success(let parsed) = requestParseResult {
            return parsed
        }
        return nil
    }

    private var parseError: String? {
        if case .failure(let message) = requestParseResult {
            return message
        }
        return nil
    }

    /// Generate a hash for deduplication
    private var contentHash: String {
        let combined = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(combined.hashValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                expandedContent
            }
        }
        .background(AppColors.substrateTertiary)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            checkIfAlreadyExecuted()
        }
    }

    private var borderColor: Color {
        switch executionState {
        case .notExecuted: return AppColors.glassBorder
        case .executing: return AppColors.signalMercury
        case .success:
            if assertionOutcome.status == .fail {
                return AppColors.signalHematite
            }
            return AppColors.signalLichen
        case .failure: return AppColors.signalHematite
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            // Tool icon and name
            if let parsed = parsedRequest {
                Image(systemName: LiveToolCall.icon(for: parsed.tool))
                    .font(.system(size: 14))
                    .foregroundColor(stateColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LiveToolCall.displayName(for: parsed.tool))
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    if let caseId = parsed.toolTestMetadata?.caseId {
                        Text(caseId)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            } else {
                Text("tool_request")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // State indicator and action button
            actionButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(stateColor.opacity(0.1))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3)) {
                isExpanded.toggle()
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch executionState {
        case .notExecuted:
            Button {
                executeToolRequest()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                    Text("Apply")
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.signalMercury)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

        case .executing:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Running...")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.signalMercury)
            }

        case .success:
            if assertionOutcome.status == .fail {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 14))
                    Text("FAIL")
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(AppColors.signalHematite)
            } else if assertionOutcome.status == .pass {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                    Text("PASS")
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(AppColors.signalLichen)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text("Applied")
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(AppColors.signalLichen)
            }

        case .failure:
            Button {
                executeToolRequest()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                    Text("Retry")
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.signalHematite)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }

    private var stateColor: Color {
        switch executionState {
        case .notExecuted: return AppColors.signalMercury
        case .executing: return AppColors.signalMercury
        case .success:
            if assertionOutcome.status == .fail {
                return AppColors.signalHematite
            }
            return AppColors.signalLichen
        case .failure: return AppColors.signalHematite
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Query preview (or show it's parameter-less)
            if let parsed = parsedRequest {
                if parsed.query.isEmpty {
                    Text("(No parameters required)")
                        .font(.system(.caption))
                        .italic()
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                } else {
                    Text(parsed.query)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(3)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
            } else {
                // Show raw JSON for debugging when parsing fails
                VStack(alignment: .leading, spacing: 4) {
                    Text("Raw JSON:")
                        .font(.system(.caption2))
                        .foregroundColor(AppColors.textTertiary)
                    Text(code)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(5)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            if let parsed = parsedRequest,
               parsed.toolTestMetadata != nil || parsed.metadataWarning != nil {
                Divider()
                    .overlay(AppColors.glassBorder.opacity(0.5))

                VStack(alignment: .leading, spacing: 4) {
                    if let metadata = parsed.toolTestMetadata {
                        Text("ToolTest run: \(metadata.runId)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(AppColors.textTertiary)

                        if executionState == .notExecuted {
                            Text("Assertions pending execution.")
                                .font(.system(.caption2))
                                .foregroundColor(AppColors.textTertiary)
                        } else {
                            Text(assertionStatusTitle)
                                .font(.system(.caption2, weight: .semibold))
                                .foregroundColor(assertionStatusColor)
                        }
                    }

                    if let warning = parsed.metadataWarning {
                        Text("Metadata warning: \(warning)")
                            .font(.system(.caption2))
                            .foregroundColor(AppColors.signalMercury)
                    }

                    if executionState != .notExecuted {
                        ForEach(Array(assertionOutcome.failureReasons.enumerated()), id: \.offset) { _, reason in
                            Text("• \(reason)")
                                .font(.system(.caption2))
                                .foregroundColor(AppColors.signalHematite)
                        }

                        ForEach(Array(assertionOutcome.notes.enumerated()), id: \.offset) { _, note in
                            Text("• \(note)")
                                .font(.system(.caption2))
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            // Result if available
            if let result = executionResult {
                Divider()
                    .overlay(AppColors.glassBorder.opacity(0.5))

                Text(result)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(executionState == .failure ? AppColors.signalHematite : AppColors.textSecondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .padding(.bottom, executionResult == nil ? 8 : 0)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var assertionStatusTitle: String {
        switch assertionOutcome.status {
        case .unavailable:
            return "Assertion status: unavailable"
        case .pass:
            if let executionDurationMs {
                return "Assertion status: PASS (\(executionDurationMs)ms)"
            }
            return "Assertion status: PASS"
        case .fail:
            if let executionDurationMs {
                return "Assertion status: FAIL (\(executionDurationMs)ms)"
            }
            return "Assertion status: FAIL"
        }
    }

    private var assertionStatusColor: Color {
        switch assertionOutcome.status {
        case .unavailable: return AppColors.textTertiary
        case .pass: return AppColors.signalLichen
        case .fail: return AppColors.signalHematite
        }
    }

    /// Check if this exact tool request was already executed in this session
    /// If auto-execute is enabled and not yet executed, triggers execution automatically
    /// IMPORTANT: Tools loaded from history (isFromHistory=true) never auto-execute
    private func checkIfAlreadyExecuted() {
        if ToolRequestTracker.shared.wasExecuted(hash: contentHash) {
            // Tool was previously executed - show completed state with result
            executionState = .success
            executionResult = ToolRequestTracker.shared.getResult(hash: contentHash)
            executionDurationMs = nil
            assertionOutcome = ToolTestAssertionEvaluator.evaluate(
                assertion: parsedRequest?.toolTestMetadata?.assertion,
                success: true,
                output: executionResult ?? "",
                durationMs: nil
            )
        } else if isFromHistory {
            // Tool is from conversation history but wasn't tracked as executed
            // Don't auto-execute - just show it as not executed (user can manually run if needed)
            // This prevents the "all tools re-execute on app rebuild" bug
            print("[ToolRequestCodeBlockView] Skipping auto-execute for history tool: \(parsedRequest?.tool ?? "unknown")")
        } else if autoExecuteEnabled && executionState == .notExecuted {
            // Newly streamed tool request - auto-execute on appear (immediate mode)
            // This is the key to decoupling display from execution
            // The tool request is in the markdown, the UI renders it, and we execute when ready
            executeToolRequest()
        }
    }

    /// Execute the tool request
    private func executeToolRequest() {
        guard let parsed = parsedRequest else {
            executionState = .failure
            // Show detailed parse error for debugging
            executionResult = parseError ?? "Failed to parse tool request (unknown error)"
            assertionOutcome = .unavailable
            return
        }

        executionState = .executing
        assertionOutcome = .unavailable
        executionDurationMs = nil

        Task {
            let startTime = Date()
            do {
                // Use unified routing service for V1/V2 compatible execution
                let result = try await ToolRoutingService.shared.executeTool(
                    toolId: parsed.tool,
                    query: parsed.query
                )
                let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                let outcome = ToolTestAssertionEvaluator.evaluate(
                    assertion: parsed.toolTestMetadata?.assertion,
                    success: result.success,
                    output: result.output,
                    durationMs: durationMs
                )

                await MainActor.run {
                    if result.success {
                        executionState = .success
                        executionResult = result.output
                        executionDurationMs = durationMs
                        assertionOutcome = outcome
                        ToolRequestTracker.shared.markExecuted(
                            hash: contentHash,
                            result: result.output
                        )
                    } else {
                        executionState = .failure
                        executionResult = result.output
                        executionDurationMs = durationMs
                        assertionOutcome = outcome
                    }
                }
            } catch {
                let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                let errorOutput = error.localizedDescription
                let outcome = ToolTestAssertionEvaluator.evaluate(
                    assertion: parsed.toolTestMetadata?.assertion,
                    success: false,
                    output: errorOutput,
                    durationMs: durationMs
                )
                await MainActor.run {
                    executionState = .failure
                    executionResult = errorOutput
                    executionDurationMs = durationMs
                    assertionOutcome = outcome
                }
            }
        }
    }
}

// MARK: - Tool Request Tracker

/// Tracks which tool requests have been executed in this session to prevent duplicates
/// Persists to UserDefaults to survive app restarts
final class ToolRequestTracker: @unchecked Sendable {
    static let shared = ToolRequestTracker()

    private var executedHashes: [String: String] = [:] // hash -> result
    private let lock = NSLock()
    private let userDefaultsKey = "ToolRequestTracker.executedHashes"

    private init() {
        // Load persisted state from disk
        if let saved = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: String] {
            executedHashes = saved
            print("[ToolRequestTracker] Loaded \(saved.count) executed tool hashes from disk")
        }
    }

    /// Persist current state to disk
    private func persistToDisk() {
        UserDefaults.standard.set(executedHashes, forKey: userDefaultsKey)
    }

    func wasExecuted(hash: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return executedHashes[hash] != nil
    }

    func markExecuted(hash: String, result: String) {
        lock.lock()
        defer { lock.unlock() }
        executedHashes[hash] = result
        persistToDisk()
    }

    func getResult(hash: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return executedHashes[hash]
    }

    /// Mark a tool request as executed using the request object
    /// Generates hash from canonical JSON representation
    func markExecuted(request: ToolRequest, result: String) {
        let json = "{\"tool\": \"\(request.tool)\", \"query\": \"\(request.query)\"}"
        let hash = String(json.trimmingCharacters(in: .whitespacesAndNewlines).hashValue)
        markExecuted(hash: hash, result: result)
    }

    /// Check if a tool request was already executed
    func wasExecuted(request: ToolRequest) -> Bool {
        let json = "{\"tool\": \"\(request.tool)\", \"query\": \"\(request.query)\"}"
        let hash = String(json.trimmingCharacters(in: .whitespacesAndNewlines).hashValue)
        return wasExecuted(hash: hash)
    }

    /// Clear all tracked executions (call on conversation switch)
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        executedHashes.removeAll()
        persistToDisk()
    }

    /// Clear persisted state completely (for debugging/reset)
    func clearPersistedState() {
        lock.lock()
        defer { lock.unlock() }
        executedHashes.removeAll()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        print("[ToolRequestTracker] Cleared all persisted tool execution state")
    }
}
