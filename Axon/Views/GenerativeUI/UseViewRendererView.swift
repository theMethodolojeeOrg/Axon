//
//  UseViewRendererView.swift
//  Axon
//
//  Renders a USEDocument as live SwiftUI via the USE-Package bridge.
//

import SwiftUI
import USECore
import USESwiftUI

/// SwiftUI host for a USE-format generative view.
/// Owns one USEBridgeState per view instance so interactive state
/// (toggles, text fields, counters) survives SwiftUI re-renders.
struct UseViewRendererView: View {
    let document: USEDocument

    @StateObject private var state = USEBridgeState()

    var body: some View {
        USEBridge(executor: USEExecutor(), state: state)
            .render(document.asDictionary())
    }
}
