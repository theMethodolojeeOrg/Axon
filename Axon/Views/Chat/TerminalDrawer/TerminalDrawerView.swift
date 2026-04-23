//
//  TerminalDrawerView.swift
//  Axon
//
//  Bottom terminal drawer shared by macOS and iPhone bridge mode.
//

import SwiftUI

struct TerminalDrawerView: View {
    @ObservedObject var controller: TerminalSessionController
    @State private var dragStartHeight: Double?

    private var sourceLabel: String {
        switch controller.workingDirectorySource {
        case .bridgeWorkspace:
            return "VS Code workspace"
        case .configuredDirectory:
            return "Default folder"
        case .home:
            return "Home"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            Rectangle()
                .fill(AppColors.glassBorder.opacity(0.55))
                .frame(width: 44, height: 4)
                .cornerRadius(2)
                .padding(.top, 8)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if dragStartHeight == nil {
                                dragStartHeight = controller.drawerHeight
                            }

                            let proposedHeight = (dragStartHeight ?? controller.drawerHeight) - value.translation.height
                            controller.drawerHeight = min(max(proposedHeight, 180), 560)
                        }
                        .onEnded { _ in
                            dragStartHeight = nil
                        }
                )
            #endif

            header

            terminalBuffer

            inputRow
        }
        .frame(height: controller.drawerHeight)
        .background(AppColors.substratePrimary)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.glassBorder.opacity(0.8))
                .frame(height: 1)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            if !controller.isRunning && controller.buffer.isEmpty {
                Task {
                    await controller.start()
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .foregroundColor(AppColors.signalMercury)

            VStack(alignment: .leading, spacing: 2) {
                Text("Terminal")
                    .font(AppTypography.bodySmall(.semibold))
                    .foregroundColor(AppColors.textPrimary)

                Text("\(sourceLabel) • \(controller.workingDirectory)")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if controller.isRunning {
                Circle()
                    .fill(AppColors.accentSuccess)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Terminal running")
            }

            iconButton("arrow.clockwise", help: "Restart Terminal") {
                controller.restart()
            }

            iconButton("trash", help: "Clear Terminal") {
                controller.clear()
            }

            iconButton("xmark", help: "Close Terminal") {
                controller.close()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.substrateSecondary.opacity(0.72))
    }

    private var terminalBuffer: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(bufferText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .id("terminal-bottom")
            }
            .background(Color.black.opacity(0.82))
            .onChange(of: controller.buffer) { _, _ in
                withAnimation(.linear(duration: 0.08)) {
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var bufferText: String {
        if let error = controller.errorMessage, controller.buffer.isEmpty {
            return error
        }
        return controller.buffer.isEmpty ? "Starting terminal..." : controller.buffer
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(AppColors.signalLichen)

            TextField("Command", text: $controller.pendingInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(AppColors.textPrimary)
                .onSubmit {
                    controller.sendPendingInput()
                }

            Button {
                controller.sendPendingInput()
            } label: {
                Image(systemName: "return")
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.plain)
            .help("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.substrateSecondary)
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

#Preview {
    TerminalDrawerView(controller: .shared)
}
