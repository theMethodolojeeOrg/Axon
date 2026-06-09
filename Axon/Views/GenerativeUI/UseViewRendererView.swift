//
//  UseViewRendererView.swift
//  Axon
//
//  Renders a USEDocument as live SwiftUI via the USE-Package bridge.
//

import Combine
import SwiftUI
import USECore
import USESwiftUI

/// Owns the per-view-instance USE runtime: one USEBridgeState and one
/// USEExecutor that survive SwiftUI re-renders. This matters for documents
/// with an "operations" section — functions defined at setup must live on
/// the same executor instance that button `call` actions later hit.
@MainActor
final class UseRenderHost: ObservableObject {
    let state = USEBridgeState()
    let executor = USEExecutor()

    @Published private(set) var lastError: String?

    private var didSetup = false

    /// Run the document's executor operations exactly once per instance.
    /// Errors fail soft: the root still renders with default state.
    func runOperationsIfNeeded(_ operations: [[String: Any]]) {
        guard !didSetup else { return }
        didSetup = true
        guard !operations.isEmpty else { return }

        // AI documents run hermetically: no file loads, no policy mutation
        executor.policy = USEViewPolicy.aiDocument

        do {
            try executor.execute(operations)
        } catch {
            lastError = "View operations failed: \(error.localizedDescription)"
            print("[UseRenderHost] \(lastError!)")
        }
    }
}

/// SwiftUI host for a USE-format generative view.
struct UseViewRendererView: View {
    let document: USEDocument
    var onError: ((String) -> Void)? = nil

    @StateObject private var host = UseRenderHost()

    var body: some View {
        USEBridge(executor: host.executor, state: host.state)
            .render(document.rootSpec)
            .task {
                host.runOperationsIfNeeded(document.operations)
                if let error = host.lastError {
                    onError?(error)
                }
            }
            #if DEBUG
            .overlay(alignment: .bottom) {
                if let error = host.lastError, onError == nil {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                        .padding(4)
                }
            }
            #endif
    }
}
