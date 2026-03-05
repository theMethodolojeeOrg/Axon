//
//  ConsoleLogList.swift
//  Axon
//
//  Scrollable log list for developer console with auto-scroll.
//

import SwiftUI

struct ConsoleLogList: View {
    let entries: [DebugLogEntry]
    let logEntriesCount: Int
    let isAutoScrollEnabled: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        DebugLogEntryRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: logEntriesCount) { _ in
                if isAutoScrollEnabled, let lastId = entries.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }
}

#Preview {
    ConsoleLogList(
        entries: [],
        logEntriesCount: 0,
        isAutoScrollEnabled: true
    )
    .background(Color.black)
}
