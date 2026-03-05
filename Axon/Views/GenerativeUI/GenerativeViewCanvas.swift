//
//  GenerativeViewCanvas.swift
//  Axon
//
//  Full-screen canvas for creating and editing generative views
//  Minimal chrome, gesture-based navigation
//

import SwiftUI

struct GenerativeViewCanvas: View {
    let initialView: GenerativeViewDefinition
    let onSave: (GenerativeViewDefinition) -> Void
    let onCancel: () -> Void

    // MARK: - State

    @State private var currentView: GenerativeViewDefinition
    @State private var snapshotView: GenerativeViewDefinition?
    @State private var hasUnsavedChanges = false

    // UI State
    @State private var isEditMode = true
    @State private var showSidebarOverlay = false
    @State private var showJSONEditor = false
    @State private var showSaveAlert = false
    @State private var showExitConfirmation = false
    @State private var showComponentPicker = false
    @State private var showPropertyEditor = false
    @State private var viewName: String

    // Selection
    @State private var selectedNodePath: [Int]? = nil

    @Environment(\.dismiss) private var dismiss

    init(initialView: GenerativeViewDefinition, onSave: @escaping (GenerativeViewDefinition) -> Void, onCancel: @escaping () -> Void) {
        self.initialView = initialView
        self.onSave = onSave
        self.onCancel = onCancel
        self._currentView = State(initialValue: initialView)
        self._viewName = State(initialValue: initialView.name)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main canvas
                canvasContent
                    .gesture(swipeGestures(in: geometry))

                // Sidebar overlay (swipe down from top)
                if showSidebarOverlay {
                    sidebarOverlay
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // JSON Editor (swipe left)
                if showJSONEditor {
                    jsonEditorPanel
                        .transition(.move(edge: .trailing))
                }

                // Top toolbar
                VStack {
                    canvasToolbar
                    Spacer()
                }
            }
            .ignoresSafeArea(.all, edges: .bottom)
        }
        .alert("Save View", isPresented: $showSaveAlert) {
            TextField("View Name", text: $viewName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                saveAndExit()
            }
        } message: {
            Text("Enter a name for this view")
        }
        .alert("Unsaved Changes", isPresented: $showExitConfirmation) {
            Button("Discard", role: .destructive) {
                onCancel()
            }
            Button("Save") {
                showSaveAlert = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. What would you like to do?")
        }
        .sheet(isPresented: $showComponentPicker) {
            ComponentPickerSheet(
                onSelect: { componentType in
                    addComponent(type: componentType)
                    showComponentPicker = false
                },
                onCancel: {
                    showComponentPicker = false
                }
            )
        }
        .sheet(isPresented: $showPropertyEditor) {
            if let path = selectedNodePath, let node = getNode(at: path) {
                PropertyEditorSheet(
                    node: node,
                    onSave: { updatedNode in
                        updateNode(at: path, with: updatedNode)
                        showPropertyEditor = false
                    },
                    onCancel: {
                        showPropertyEditor = false
                    },
                    onDelete: {
                        deleteNode(at: path)
                        showPropertyEditor = false
                    }
                )
            }
        }
        .onAppear {
            snapshotView = initialView
        }
        #if os(iOS)
        .statusBarHidden(true)
        #endif
    }

    // MARK: - Canvas Content

    private var canvasContent: some View {
        ZStack {
            AppColors.substratePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 80) // Space for toolbar

                    // Device frame preview
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(AppColors.substratePrimary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(isEditMode ? AppColors.signalCopper : AppColors.dividerStrong, lineWidth: isEditMode ? 2 : 1)
                            )

                        // Rendered content
                        if isEditMode {
                            EditableNodeView(
                                node: currentView.root,
                                path: [],
                                isEditMode: $isEditMode,
                                onTap: { path in
                                    selectedNodePath = path
                                    showPropertyEditor = true
                                },
                                onMove: { fromPath, toIndex in
                                    moveNode(from: fromPath, toIndex: toIndex)
                                }
                            )
                            .padding()
                        } else {
                            GenerativeUIRenderer.render(currentView.root)
                                .padding()
                        }
                    }
                    .frame(width: 320, height: 568)
                    .shadow(color: AppColors.shadow, radius: 10, x: 0, y: 5)
                    .padding()

                    Spacer()
                        .frame(height: 100)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Toolbar

    private var canvasToolbar: some View {
        HStack {
            // Close button
            Button {
                attemptExit()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(AppColors.substrateSecondary.opacity(0.9))
                    .clipShape(Circle())
            }

            Spacer()

            // Title
            VStack(spacing: 2) {
                Text(viewName)
                    .font(AppTypography.titleSmall())
                    .foregroundColor(AppColors.textPrimary)

                if hasUnsavedChanges {
                    Text("Edited")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalCopper)
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                // Add component
                Button {
                    showComponentPicker = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppColors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(AppColors.substrateSecondary.opacity(0.9))
                        .clipShape(Circle())
                }

                // Save button
                Button {
                    showSaveAlert = true
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(AppColors.signalLichen)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [AppColors.substratePrimary, AppColors.substratePrimary.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Sidebar Overlay

    private var sidebarOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(AppAnimations.standardEasing) {
                        showSidebarOverlay = false
                    }
                }

            VStack {
                GenerativeViewSidebarOverlay(
                    onSelectView: { view in
                        // Switch to another view (would need to save first)
                        withAnimation {
                            showSidebarOverlay = false
                        }
                    },
                    onClose: {
                        withAnimation(AppAnimations.standardEasing) {
                            showSidebarOverlay = false
                        }
                    }
                )
                .frame(maxHeight: 400)

                Spacer()
            }
        }
    }

    // MARK: - JSON Editor Panel

    private var jsonEditorPanel: some View {
        HStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("JSON Editor")
                        .font(AppTypography.titleSmall())
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Button {
                        withAnimation(AppAnimations.standardEasing) {
                            showJSONEditor = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding()
                .background(AppColors.substrateSecondary)

                // JSON content
                ScrollView {
                    Text(jsonString)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(AppColors.substratePrimary)
            }
            .frame(width: 320)
            .background(AppColors.substratePrimary)
            .overlay(
                Rectangle()
                    .fill(AppColors.dividerStrong)
                    .frame(width: 1),
                alignment: .leading
            )
        }
    }

    private var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(currentView.root),
              let json = String(data: data, encoding: .utf8) else {
            return "Error encoding JSON"
        }
        return json
    }

    // MARK: - Gestures

    private func swipeGestures(in geometry: GeometryProxy) -> some Gesture {
        DragGesture()
            .onEnded { value in
                let threshold: CGFloat = 80

                // Swipe down from top (reveal sidebar)
                if value.startLocation.y < 60 && value.translation.height > threshold {
                    withAnimation(AppAnimations.standardEasing) {
                        showSidebarOverlay = true
                    }
                    return
                }

                // Swipe right (exit)
                if value.translation.width > threshold && abs(value.translation.height) < threshold {
                    attemptExit()
                    return
                }

                // Swipe left (JSON editor)
                if value.translation.width < -threshold && abs(value.translation.height) < threshold {
                    withAnimation(AppAnimations.standardEasing) {
                        showJSONEditor.toggle()
                    }
                }
            }
    }

    // MARK: - Actions

    private func attemptExit() {
        if hasUnsavedChanges {
            showExitConfirmation = true
        } else {
            onCancel()
        }
    }

    private func saveAndExit() {
        var finalView = currentView
        finalView.rename(to: viewName)
        onSave(finalView)
    }

    // MARK: - Node Manipulation

    private func getNode(at path: [Int]) -> GenerativeUINode? {
        var node = currentView.root

        for index in path {
            guard let children = node.children, index < children.count else { return nil }
            node = children[index]
        }

        return node
    }

    private func updateNode(at path: [Int], with newNode: GenerativeUINode) {
        var root = currentView.root

        if path.isEmpty {
            root = newNode
        } else {
            updateNodeRecursive(node: &root, path: path, newNode: newNode)
        }

        currentView.update(root: root)
        hasUnsavedChanges = true
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
        guard !path.isEmpty else { return }

        var root = currentView.root
        deleteNodeRecursive(node: &root, path: path)
        currentView.update(root: root)
        hasUnsavedChanges = true
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
        guard !sourcePath.isEmpty else { return }

        var root = currentView.root
        let parentPath = Array(sourcePath.dropLast())
        let sourceIndex = sourcePath.last!

        if parentPath.isEmpty {
            guard var children = root.children, sourceIndex < children.count else { return }
            let node = children.remove(at: sourceIndex)
            let adjustedIndex = toIndex > sourceIndex ? toIndex - 1 : toIndex
            children.insert(node, at: min(adjustedIndex, children.count))
            root.children = children
        } else {
            moveNodeRecursive(node: &root, parentPath: parentPath, sourceIndex: sourceIndex, toIndex: toIndex)
        }

        currentView.update(root: root)
        hasUnsavedChanges = true
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

    private func addComponent(type: GenerativeUIComponentType) {
        var root = currentView.root

        // Create new node based on type
        let newNode: GenerativeUINode
        switch type {
        case .vstack:
            newNode = .vstack(spacing: 8, children: [])
        case .hstack:
            newNode = .hstack(spacing: 8, children: [])
        case .zstack:
            newNode = GenerativeUINode(
                type: .zstack,
                properties: GenerativeUIProperties(keys: [], values: []),
                children: []
            )
        case .text:
            newNode = .text("New Text", font: "bodyMedium")
        case .button:
            newNode = .button("Button")
        case .spacer:
            newNode = .spacer()
        case .divider:
            newNode = GenerativeUINode(
                type: .divider,
                properties: GenerativeUIProperties(keys: [], values: []),
                children: nil
            )
        case .image:
            newNode = GenerativeUINode(
                type: .image,
                properties: GenerativeUIProperties(
                    keys: ["systemName", "color"],
                    values: [.string("star.fill"), .string("mercury")]
                ),
                children: nil
            )
        }

        // Add to root's children
        var children = root.children ?? []
        children.append(newNode)
        root.children = children

        currentView.update(root: root)
        hasUnsavedChanges = true
    }
}
