//
//  BridgeLogInspector.swift
//  Axon
//
//  Inspector view for viewing VS Code Bridge WebSocket traffic logs.
//

import SwiftUI

struct BridgeLogInspector: View {
    @ObservedObject var logService = BridgeLogService.shared
    @State private var searchText = ""
    @State private var selectedEntry: BridgeLogEntry?

    var body: some View {
        HStack(spacing: 0) {
            BridgeLogInspectorListPane(
                logService: logService,
                searchText: $searchText,
                selectedEntry: $selectedEntry
            )
            .frame(minWidth: 300)

            Divider()

            BridgeLogInspectorDetailPane(selectedEntry: selectedEntry, logService: logService)
                .frame(minWidth: 400)
        }
        .background(AppColors.substratePrimary)
        .navigationTitle("Bridge Inspector")
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    AppClipboard.copy(logService.export())
                }) {
                    Label("Export JSON", systemImage: "square.and.arrow.up")
                }
            }
        }
        #endif
    }
}
