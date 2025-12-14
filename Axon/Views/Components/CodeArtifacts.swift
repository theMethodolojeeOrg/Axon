//
//  CodeArtifacts.swift
//  Axon
//
//  ChatGPT/Claude-like code blocks + “artifact” expansion UI.
//

import SwiftUI

#if os(macOS)
import AppKit
import Combine
import UniformTypeIdentifiers
#endif

// MARK: - Model

struct CodeArtifact: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let language: String?
    let code: String

    var fileExtension: String {
        // Map common language tags to file extensions.
        switch (language ?? "").lowercased() {
        case "swift": return "swift"
        case "py", "python": return "py"
        case "js", "javascript": return "js"
        case "ts", "typescript": return "ts"
        case "json": return "json"
        case "yaml", "yml": return "yml"
        case "md", "markdown": return "md"
        case "html": return "html"
        case "css": return "css"
        case "sh", "bash", "zsh": return "sh"
        case "sql": return "sql"
        case "c": return "c"
        case "cpp", "c++": return "cpp"
        case "h", "hpp": return "h"
        case "java": return "java"
        case "kt", "kotlin": return "kt"
        case "go": return "go"
        case "rs", "rust": return "rs"
        default: return "txt"
        }
    }

    var exportFileURL: URL {
        let base = (title.isEmpty ? "code" : title)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(base).\(fileExtension)"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? code.data(using: .utf8)?.write(to: url, options: [.atomic])
        return url
    }
}

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
    @Published var selected: CodeArtifact? = nil

    /// Most recently presented artifact (fallback when nothing is selected).
    @Published var lastSeen: CodeArtifact? = nil

    /// Right inspector column open/closed.
    @Published var isOpen: Bool = false

    /// Width of the inspector (resizable).
    @Published var inspectorWidth: CGFloat = 480

    /// Currently active inspector tab.
    @Published var activeTab: InspectorTab = .code

    /// Minimum and maximum widths for resizing.
    static let minWidth: CGFloat = 320
    static let maxWidth: CGFloat = 800

    func present(_ artifact: CodeArtifact) {
        lastSeen = artifact
        selected = artifact
        activeTab = .code
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isOpen = true
        }
    }

    func showBridgeLogs() {
        activeTab = .bridgeLogs
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
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
    static var defaultValue: ((CodeArtifact) -> Void)? = nil
}

extension EnvironmentValues {
    var presentCodeArtifact: ((CodeArtifact) -> Void)? {
        get { self[CodeArtifactPresenterKey.self] }
        set { self[CodeArtifactPresenterKey.self] = newValue }
    }
}

// MARK: - Artifact View

struct CodeArtifactView: View {
    let artifact: CodeArtifact

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var showExportSheet = false
    @State private var wrapLines = true

    #if os(macOS)
    private func saveOnMacOS() {
        // Use NSSavePanel so the user can pick filename + location.
        let panel = NSSavePanel()
        panel.nameFieldStringValue = artifact.exportFileURL.lastPathComponent
        panel.allowedFileTypes = [artifact.fileExtension]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try artifact.code.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("[CodeArtifactView] Failed to save file: \(error)")
            }
        }
    }
    #endif

    private var languageLabel: String {
        let raw = artifact.language?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false ? raw! : "code")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(AppColors.glassBorder.opacity(0.6))

            ScrollView([.vertical, .horizontal]) {
                Text(artifact.code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: wrapLines ? .infinity : nil, alignment: .leading)
                    .fixedSize(horizontal: wrapLines, vertical: true)
            }
            .background(AppColors.substratePrimary)
        }
        .background(AppColors.substratePrimary)
        .sheet(isPresented: $showExportSheet) {
            #if canImport(UIKit)
            ActivityView(activityItems: [artifact.exportFileURL])
            #else
            EmptyView()
            #endif
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(8)
                    .background(
                        Circle().fill(AppColors.substrateSecondary)
                    )
            }
            .buttonStyle(.plain)

            Text(artifact.title)
                .font(AppTypography.titleSmall())
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(languageLabel)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(AppColors.substrateSecondary)
                )

            Toggle(isOn: $wrapLines) {
                Text("Wrap")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }
            .toggleStyle(.switch)
            .labelsHidden()

            Button {
                #if os(macOS)
                saveOnMacOS()
                #else
                showExportSheet = true
                #endif
            } label: {
                Label("Download", systemImage: "square.and.arrow.down")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppColors.substrateSecondary)
                    )
            }
            .buttonStyle(.plain)

            Button {
                AppClipboard.copy(artifact.code)
                withAnimation(.easeInOut(duration: 0.15)) {
                    copied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        copied = false
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                    Text(copied ? "Copied" : "Copy")
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(copied ? AppColors.signalLichen : AppColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColors.substrateSecondary)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(AppColors.substratePrimary)
    }
}

// MARK: - Code Block View (inline)

struct CodeBlockView<Content: View>: View {
    let language: String?
    let code: String
    let content: Content

    init(language: String? = nil, code: String, @ViewBuilder content: () -> Content) {
        self.language = language
        self.code = code
        self.content = content()
    }

    @Environment(\.presentCodeArtifact) private var presentArtifact
    @State private var copied = false

    private var languageLabel: String {
        let raw = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false ? raw! : "code")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.horizontal, showsIndicators: true) {
                content
                    .padding(12)
            }
            .background(AppColors.substrateTertiary)
        }
        .background(AppColors.substrateTertiary)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(languageLabel)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(AppColors.substrateSecondary)
                )

            Spacer()

            // Send to Inspector button
            Button {
                let artifact = CodeArtifact(
                    title: "Code",
                    language: language,
                    code: code
                )
                presentArtifact?(artifact)
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
}

// MARK: - Host modifier

/// iOS uses sheet-based presentation; macOS relies on the inspector set higher up.
struct CodeArtifactHost: ViewModifier {
    @State private var selected: CodeArtifact? = nil

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
            .sheet(item: $selected) { artifact in
                CodeArtifactView(artifact: artifact)
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

    private var artifactToShow: CodeArtifact? {
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
                    BridgeLogInspectorView()
                }
            }
        }
        .frame(width: presenter.inspectorWidth)
        .frame(maxHeight: .infinity)
        .background(AppColors.substratePrimary)
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
                        action: { presenter.activeTab = tab }
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

    private func inspectorArtifactView(artifact: CodeArtifact) -> some View {
        VStack(spacing: 0) {
            // Artifact header with language badge
            HStack(spacing: 10) {
                Text(artifact.title.isEmpty ? "Code" : artifact.title)
                    .font(AppTypography.titleSmall())
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                let lang = artifact.language?.trimmingCharacters(in: .whitespacesAndNewlines)
                Text((lang?.isEmpty == false ? lang! : "code"))
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(AppColors.substrateSecondary)
                    )

                // Copy button
                InspectorCopyButton(code: artifact.code)

                // Download button
                InspectorDownloadButton(artifact: artifact)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.substrateElevated.opacity(0.3))

            Divider()
                .overlay(AppColors.glassBorder.opacity(0.4))

            // Code content
            ScrollView([.vertical, .horizontal]) {
                Text(artifact.code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.substratePrimary)
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

// MARK: - Inspector Helper Views

private struct InspectorCopyButton: View {
    let code: String
    @State private var copied = false

    var body: some View {
        Button {
            AppClipboard.copy(code)
            withAnimation(.easeInOut(duration: 0.15)) {
                copied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
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
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppColors.substrateSecondary)
                )
        }
        .buttonStyle(.plain)
        .help("Copy Code")
    }
}

private struct InspectorDownloadButton: View {
    let artifact: CodeArtifact

    var body: some View {
        Button {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = artifact.exportFileURL.lastPathComponent
            panel.allowedContentTypes = [.plainText]
            panel.canCreateDirectories = true

            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try artifact.code.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("[InspectorDownloadButton] Failed to save: \(error)")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.textSecondary)
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppColors.substrateSecondary)
                )
        }
        .buttonStyle(.plain)
        .help("Save As…")
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
