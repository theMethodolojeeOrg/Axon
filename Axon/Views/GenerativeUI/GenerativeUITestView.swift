//
//  GenerativeUITestView.swift
//  Axon
//
//  Test view for experimenting with JSON-driven generative UI
//  Split-pane: JSON editor on left, live preview on right
//  Visual edit mode: long-press to enter, drag to reorder, tap to edit properties
//

import Foundation
import SwiftUI

struct GenerativeUITestView: View {
    @State private var jsonText: String = ""
    @State private var parsedNode: GenerativeUINode?
    @State private var parseError: String?
    @State private var showingHelp = false

    // Visual edit mode state
    @State private var isEditMode = false
    @State private var snapshotJSON: String = ""  // Original JSON before editing
    @State private var selectedNodePath: [Int]? = nil  // Path to selected node for editing
    @State private var showingPropertyEditor = false

    var body: some View {
        #if os(macOS)
        HSplitView {
            editorPane
            previewPane
        }
        .onAppear {
            loadDefaultJSON()
        }
        .navigationTitle("Generative UI Sandbox")
        .toolbar {
            ToolbarItem {
                Button(action: resetToDefault) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .help("Reset to default JSON")
            }
            ToolbarItem {
                Button(action: { showingHelp = true }) {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .help("Show component reference")
            }
        }
        .sheet(isPresented: $showingHelp) {
            helpSheet
        }
        .sheet(isPresented: $showingPropertyEditor) {
            if let path = selectedNodePath, let node = getNode(at: path) {
                PropertyEditorSheet(
                    node: node,
                    onSave: { updatedNode in
                        updateNode(at: path, with: updatedNode)
                        showingPropertyEditor = false
                    },
                    onCancel: {
                        showingPropertyEditor = false
                    },
                    onDelete: {
                        deleteNode(at: path)
                        showingPropertyEditor = false
                    }
                )
            }
        }
        #else
        NavigationStack {
            VStack(spacing: 0) {
                // iOS: Use tabs or segmented control
                TabView {
                    editorPane
                        .tabItem {
                            Label("JSON", systemImage: "curlybraces")
                        }
                    previewPane
                        .tabItem {
                            Label("Preview", systemImage: "eye")
                        }
                }
            }
            .navigationTitle("Generative UI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: resetToDefault) {
                            Label("Reset to Default", systemImage: "arrow.counterclockwise")
                        }
                        Button(action: { showingHelp = true }) {
                            Label("Component Reference", systemImage: "questionmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingHelp) {
                helpSheet
            }
            .sheet(isPresented: $showingPropertyEditor) {
                if let path = selectedNodePath, let node = getNode(at: path) {
                    PropertyEditorSheet(
                        node: node,
                        onSave: { updatedNode in
                            updateNode(at: path, with: updatedNode)
                            showingPropertyEditor = false
                        },
                        onCancel: {
                            showingPropertyEditor = false
                        },
                        onDelete: {
                            deleteNode(at: path)
                            showingPropertyEditor = false
                        }
                    )
                }
            }
            .onAppear {
                loadDefaultJSON()
            }
        }
        #endif
    }

    // MARK: - Editor Pane

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "curlybraces")
                    .foregroundColor(AppColors.signalMercury)
                Text("JSON Editor")
                    .font(AppTypography.titleMedium())
                    .foregroundColor(AppColors.textPrimary)
                Spacer()

                // Status indicator
                if parseError != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Error")
                    }
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.accentError)
                } else if parsedNode != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Valid")
                    }
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.accentSuccess)
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)

            Divider()

            // Text editor
            TextEditor(text: $jsonText)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(AppColors.substratePrimary)
                .onChange(of: jsonText) { _, newValue in
                    parseJSON(newValue)
                }

            // Error display
            if let error = parseError {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.accentError)
                        Text(error)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.accentError)
                            .textSelection(.enabled)
                    }
                    .padding()
                }
                .background(AppColors.accentError.opacity(0.1))
            }
        }
        .frame(minWidth: 300, idealWidth: 400)
    }

    // MARK: - Preview Pane

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with edit mode toggle
            HStack {
                Image(systemName: isEditMode ? "pencil.circle.fill" : "eye")
                    .foregroundColor(isEditMode ? AppColors.signalCopper : AppColors.signalLichen)
                Text(isEditMode ? "Edit Mode" : "Live Preview")
                    .font(AppTypography.titleMedium())
                    .foregroundColor(AppColors.textPrimary)
                Spacer()

                if isEditMode {
                    // Edit mode toolbar
                    HStack(spacing: 12) {
                        Button(action: cancelEditMode) {
                            Text("Cancel")
                                .font(AppTypography.labelMedium())
                        }
                        .buttonStyle(.bordered)

                        Button(action: saveEditMode) {
                            Text("Save")
                                .font(AppTypography.labelMedium())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.signalLichen)
                    }
                } else {
                    if let node = parsedNode {
                        Text("\(countNodes(node)) nodes")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Button(action: enterEditMode) {
                        Label("Edit", systemImage: "pencil")
                            .font(AppTypography.labelMedium())
                    }
                    .buttonStyle(.bordered)
                    .disabled(parsedNode == nil)
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)

            Divider()

            // Preview area
            ScrollView {
                if let node = parsedNode {
                    VStack {
                        // Device frame
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(AppColors.substratePrimary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(isEditMode ? AppColors.signalCopper : AppColors.dividerStrong, lineWidth: isEditMode ? 2 : 1)
                                )

                            // Rendered content with edit mode wrapper
                            if isEditMode {
                                EditableNodeView(
                                    node: node,
                                    path: [],
                                    isEditMode: $isEditMode,
                                    onTap: { path in
                                        selectedNodePath = path
                                        showingPropertyEditor = true
                                    },
                                    onMove: { fromPath, toIndex in
                                        moveNode(from: fromPath, toIndex: toIndex)
                                    }
                                )
                                .padding()
                            } else {
                                GenerativeUIRenderer.render(node)
                                    .padding()
                            }
                        }
                        .frame(width: 320, height: 568)
                        .shadow(color: AppColors.shadow, radius: 10, x: 0, y: 5)
                        .animation(.easeInOut(duration: 0.3), value: isEditMode)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "rectangle.dashed")
                            .font(.system(size: 48))
                            .foregroundColor(AppColors.textTertiary)
                        Text("No valid layout")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textSecondary)
                        Text("Fix the JSON errors to see a preview")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(AppColors.substrateTertiary)
        }
        .frame(minWidth: 400)
    }

    // MARK: - Help Sheet

    private var helpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    componentSection(
                        title: "Layout Components",
                        components: [
                            ("VStack", "Vertical stack", "spacing, alignment (leading/center/trailing)"),
                            ("HStack", "Horizontal stack", "spacing, alignment (top/center/bottom)"),
                            ("ZStack", "Overlay stack", "alignment (topLeading, center, etc.)"),
                            ("Spacer", "Flexible space", "minLength"),
                            ("Divider", "Separator line", "(none)")
                        ]
                    )

                    componentSection(
                        title: "Content Components",
                        components: [
                            ("Text", "Display text", "text, font, color"),
                            ("Button", "Tappable button", "label, style"),
                            ("Image", "SF Symbol or asset", "systemName OR name, color")
                        ]
                    )

                    fontSection

                    colorSection

                    editModeSection
                }
                .padding()
            }
            .navigationTitle("Component Reference")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingHelp = false }
                }
            }
        }
        #if os(macOS)
        .frame(width: 500, height: 600)
        #endif
    }

    private func componentSection(title: String, components: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.textPrimary)

            ForEach(components, id: \.0) { name, description, properties in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(name)
                            .font(AppTypography.code())
                            .foregroundColor(AppColors.signalMercury)
                        Text("- \(description)")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                    Text("Properties: \(properties)")
                        .font(AppTypography.codeSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.leading, 8)
            }
        }
    }

    private var fontSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Font Values")
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach([
                    "titleLarge", "titleMedium", "titleSmall",
                    "bodyLarge", "bodyMedium", "bodySmall",
                    "labelLarge", "labelMedium", "labelSmall",
                    "code", "codeSmall"
                ], id: \.self) { font in
                    Text(font)
                        .font(AppTypography.codeSmall())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(4)
                }
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color Values")
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach([
                    ("textPrimary", AppColors.textPrimary),
                    ("textSecondary", AppColors.textSecondary),
                    ("mercury", AppColors.signalMercury),
                    ("lichen", AppColors.signalLichen),
                    ("copper", AppColors.signalCopper),
                    ("success", AppColors.accentSuccess),
                    ("warning", AppColors.accentWarning),
                    ("error", AppColors.accentError)
                ], id: \.0) { name, color in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color)
                            .frame(width: 16, height: 16)
                        Text(name)
                            .font(AppTypography.codeSmall())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(4)
                }
            }
        }
    }

    private var editModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visual Edit Mode")
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Label("Tap \"Edit\" to enter visual edit mode", systemImage: "pencil")
                Label("Tap any element to edit its properties", systemImage: "hand.tap")
                Label("Drag elements to reorder within containers", systemImage: "arrow.up.arrow.down")
                Label("Tap \"Save\" to keep changes or \"Cancel\" to revert", systemImage: "checkmark.circle")
            }
            .font(AppTypography.bodySmall())
            .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - JSON Loading & Parsing

    private func loadDefaultJSON() {
        // Try to load from bundle first
        if let url = Bundle.main.url(forResource: "default_layout", withExtension: "json", subdirectory: "GenerativeUI"),
           let data = try? Data(contentsOf: url),
           let json = String(data: data, encoding: .utf8) {
            jsonText = json
        } else {
            // Fallback to inline default
            jsonText = Self.fallbackJSON
        }
        parseJSON(jsonText)
    }

    private func parseJSON(_ json: String) {
        do {
            guard let data = json.data(using: .utf8) else {
                parseError = "Invalid UTF-8 encoding"
                parsedNode = nil
                return
            }

            let decoder = JSONDecoder()
            parsedNode = try decoder.decode(GenerativeUINode.self, from: data)
            parseError = nil
        } catch let error as DecodingError {
            parseError = formatDecodingError(error)
            parsedNode = nil
        } catch {
            parseError = error.localizedDescription
            parsedNode = nil
        }
    }

    private func formatDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return "Type mismatch: expected \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "Value not found: expected \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .keyNotFound(let key, _):
            return "Missing key: '\(key.stringValue)'"
        case .dataCorrupted(let context):
            return "Data corrupted: \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private func countNodes(_ node: GenerativeUINode) -> Int {
        var count = 1
        if let children = node.children {
            for child in children {
                count += countNodes(child)
            }
        }
        return count
    }

    private func resetToDefault() {
        loadDefaultJSON()
    }

    // MARK: - Edit Mode

    private func enterEditMode() {
        snapshotJSON = jsonText
        isEditMode = true
    }

    private func cancelEditMode() {
        jsonText = snapshotJSON
        parseJSON(jsonText)
        isEditMode = false
        selectedNodePath = nil
    }

    private func saveEditMode() {
        // JSON is already updated, just exit edit mode
        isEditMode = false
        selectedNodePath = nil
        snapshotJSON = ""
    }

    // MARK: - Node Manipulation

    private func getNode(at path: [Int]) -> GenerativeUINode? {
        guard var node = parsedNode else { return nil }

        for index in path {
            guard let children = node.children, index < children.count else { return nil }
            node = children[index]
        }

        return node
    }

    private func updateNode(at path: [Int], with newNode: GenerativeUINode) {
        guard var root = parsedNode else { return }

        if path.isEmpty {
            // Updating root node
            parsedNode = newNode
        } else {
            // Navigate to parent and update child
            updateNodeRecursive(node: &root, path: path, newNode: newNode)
            parsedNode = root
        }

        // Update JSON text
        updateJSONFromNode()
    }

    private func updateNodeRecursive(node: inout GenerativeUINode, path: [Int], newNode: GenerativeUINode) {
        guard !path.isEmpty else { return }

        let index = path[0]
        guard var children = node.children, index < children.count else { return }

        if path.count == 1 {
            children[index] = newNode
            node.children = children
        } else {
            var child = children[index]
            updateNodeRecursive(node: &child, path: Array(path.dropFirst()), newNode: newNode)
            children[index] = child
            node.children = children
        }
    }

    private func deleteNode(at path: [Int]) {
        guard var root = parsedNode, !path.isEmpty else { return }

        deleteNodeRecursive(node: &root, path: path)
        parsedNode = root
        updateJSONFromNode()
    }

    private func deleteNodeRecursive(node: inout GenerativeUINode, path: [Int]) {
        guard !path.isEmpty else { return }

        let index = path[0]
        guard var children = node.children, index < children.count else { return }

        if path.count == 1 {
            children.remove(at: index)
            node.children = children.isEmpty ? nil : children
        } else {
            var child = children[index]
            deleteNodeRecursive(node: &child, path: Array(path.dropFirst()))
            children[index] = child
            node.children = children
        }
    }

    private func moveNode(from sourcePath: [Int], toIndex: Int) {
        guard var root = parsedNode, !sourcePath.isEmpty else { return }

        // Get parent path and child index
        let parentPath = Array(sourcePath.dropLast())
        let sourceIndex = sourcePath.last!

        // Navigate to parent
        if parentPath.isEmpty {
            // Moving within root's children
            guard var children = root.children, sourceIndex < children.count else { return }
            let node = children.remove(at: sourceIndex)
            let adjustedIndex = toIndex > sourceIndex ? toIndex - 1 : toIndex
            children.insert(node, at: min(adjustedIndex, children.count))
            root.children = children
            parsedNode = root
        } else {
            // Moving within nested container
            moveNodeRecursive(node: &root, parentPath: parentPath, sourceIndex: sourceIndex, toIndex: toIndex)
            parsedNode = root
        }

        updateJSONFromNode()
    }

    private func moveNodeRecursive(node: inout GenerativeUINode, parentPath: [Int], sourceIndex: Int, toIndex: Int) {
        guard !parentPath.isEmpty else {
            guard var children = node.children, sourceIndex < children.count else { return }
            let movedNode = children.remove(at: sourceIndex)
            let adjustedIndex = toIndex > sourceIndex ? toIndex - 1 : toIndex
            children.insert(movedNode, at: min(adjustedIndex, children.count))
            node.children = children
            return
        }

        let index = parentPath[0]
        guard var children = node.children, index < children.count else { return }

        var child = children[index]
        moveNodeRecursive(node: &child, parentPath: Array(parentPath.dropFirst()), sourceIndex: sourceIndex, toIndex: toIndex)
        children[index] = child
        node.children = children
    }

    private func updateJSONFromNode() {
        guard let node = parsedNode else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(node),
           let json = String(data: data, encoding: .utf8) {
            jsonText = json
        }
    }

    // MARK: - Fallback JSON

    static let fallbackJSON = """
{
  "type": "VStack",
  "properties": {
    "keys": ["spacing"],
    "values": [16]
  },
  "children": [
    {
      "type": "Text",
      "properties": {
        "keys": ["text", "font"],
        "values": ["Hello, Generative UI!", "titleLarge"]
      }
    },
    {
      "type": "Text",
      "properties": {
        "keys": ["text"],
        "values": ["Bundle file not found - using fallback"]
      }
    }
  ]
}
"""
}

// MARK: - Editable Node View (with jiggle animation)

struct EditableNodeView: View {
    let node: GenerativeUINode
    let path: [Int]
    @Binding var isEditMode: Bool
    let onTap: ([Int]) -> Void
    let onMove: ([Int], Int) -> Void

    @State private var jiggleRotation: Double = 0

    var body: some View {
        nodeContent
            .contentShape(Rectangle())
            .onTapGesture {
                onTap(path)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(AppColors.signalCopper.opacity(0.5), lineWidth: 1)
                    .padding(-2)
            )
            .rotationEffect(.degrees(jiggleRotation))
            .onAppear {
                startJiggle()
            }
            .onDisappear {
                jiggleRotation = 0
            }
    }

    @ViewBuilder
    private var nodeContent: some View {
        switch node.type {
        case .vstack:
            VStack(alignment: resolveHAlignment(), spacing: node.properties["spacing"]?.doubleValue ?? 8) {
                if let children = node.children {
                    ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                        EditableNodeView(
                            node: child,
                            path: path + [index],
                            isEditMode: $isEditMode,
                            onTap: onTap,
                            onMove: onMove
                        )
                    }
                }
            }

        case .hstack:
            HStack(alignment: resolveVAlignment(), spacing: node.properties["spacing"]?.doubleValue ?? 8) {
                if let children = node.children {
                    ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                        EditableNodeView(
                            node: child,
                            path: path + [index],
                            isEditMode: $isEditMode,
                            onTap: onTap,
                            onMove: onMove
                        )
                    }
                }
            }

        case .zstack:
            ZStack {
                if let children = node.children {
                    ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                        EditableNodeView(
                            node: child,
                            path: path + [index],
                            isEditMode: $isEditMode,
                            onTap: onTap,
                            onMove: onMove
                        )
                    }
                }
            }

        case .text:
            Text(node.properties["text"]?.stringValue ?? "")
                .font(GenerativeUIRenderer.resolveFont(node.properties["font"]?.stringValue))
                .foregroundColor(GenerativeUIRenderer.resolveColor(node.properties["color"]?.stringValue))

        case .button:
            Button(action: {}) {
                Text(node.properties["label"]?.stringValue ?? "Button")
            }
            .buttonStyle(.borderedProminent)

        case .spacer:
            Spacer(minLength: node.properties["minLength"]?.doubleValue.map { CGFloat($0) } ?? nil)
                .frame(minHeight: 20)
                .background(AppColors.signalCopper.opacity(0.1))

        case .divider:
            Divider()

        case .image:
            if let systemName = node.properties["systemName"]?.stringValue {
                Image(systemName: systemName)
                    .foregroundColor(GenerativeUIRenderer.resolveColor(node.properties["color"]?.stringValue))
            } else {
                Image(systemName: "photo")
                    .foregroundColor(AppColors.textTertiary)
            }
        }
    }

    private func resolveHAlignment() -> HorizontalAlignment {
        guard let name = node.properties["alignment"]?.stringValue else { return .center }
        switch name.lowercased() {
        case "leading", "left": return .leading
        case "trailing", "right": return .trailing
        default: return .center
        }
    }

    private func resolveVAlignment() -> VerticalAlignment {
        guard let name = node.properties["alignment"]?.stringValue else { return .center }
        switch name.lowercased() {
        case "top": return .top
        case "bottom": return .bottom
        default: return .center
        }
    }

    private func startJiggle() {
        // Slight random offset so not all elements jiggle in sync
        let delay = Double.random(in: 0...0.1)

        withAnimation(
            Animation
                .easeInOut(duration: 0.1)
                .repeatForever(autoreverses: true)
                .delay(delay)
        ) {
            jiggleRotation = Double.random(in: -1.5...1.5)
        }
    }
}

// MARK: - Property Editor Sheet

struct PropertyEditorSheet: View {
    let node: GenerativeUINode
    let onSave: (GenerativeUINode) -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var editedProperties: [(key: String, value: String)] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Component Type") {
                    HStack {
                        Image(systemName: iconForType(node.type))
                            .foregroundColor(AppColors.signalMercury)
                        Text(node.type.rawValue)
                            .font(AppTypography.bodyMedium(.medium))
                    }
                }

                Section("Properties") {
                    ForEach(editedProperties.indices, id: \.self) { index in
                        HStack {
                            Text(editedProperties[index].key)
                                .font(AppTypography.code())
                                .foregroundColor(AppColors.textSecondary)
                                .frame(width: 100, alignment: .leading)

                            TextField("Value", text: $editedProperties[index].value)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Button(action: addProperty) {
                        Label("Add Property", systemImage: "plus.circle")
                    }
                }

                Section {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Component", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit \(node.type.rawValue)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                }
            }
            .onAppear {
                loadProperties()
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 400)
        #endif
    }

    private func loadProperties() {
        editedProperties = zip(node.properties.keys, node.properties.values).map { key, value in
            (key: key, value: valueToString(value))
        }
    }

    private func valueToString(_ value: AnyCodable) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        default: return ""
        }
    }

    private func stringToValue(_ string: String) -> AnyCodable {
        // Try to parse as number first
        if let intVal = Int(string) {
            return .int(intVal)
        } else if let doubleVal = Double(string) {
            return .double(doubleVal)
        } else if string.lowercased() == "true" {
            return .bool(true)
        } else if string.lowercased() == "false" {
            return .bool(false)
        } else {
            return .string(string)
        }
    }

    private func addProperty() {
        editedProperties.append((key: "newProperty", value: ""))
    }

    private func saveChanges() {
        let keys = editedProperties.map { $0.key }
        let values = editedProperties.map { stringToValue($0.value) }

        let newProperties = GenerativeUIProperties(keys: keys, values: values)
        let updatedNode = GenerativeUINode(
            type: node.type,
            properties: newProperties,
            children: node.children
        )

        onSave(updatedNode)
    }

    private func iconForType(_ type: GenerativeUIComponentType) -> String {
        switch type {
        case .vstack: return "square.split.1x2"
        case .hstack: return "square.split.2x1"
        case .zstack: return "square.stack"
        case .text: return "textformat"
        case .button: return "button.horizontal"
        case .spacer: return "arrow.up.and.down"
        case .divider: return "minus"
        case .image: return "photo"
        }
    }
}

// MARK: - Preview

#Preview {
    GenerativeUITestView()
}

