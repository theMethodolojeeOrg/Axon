//
//  PerformanceSection.swift
//  Axon
//
//  Performance settings for Live Voice mode
//

import SwiftUI

/// Section for latency and real-time performance settings
struct PerformanceSection: View {
    @Binding var latencyMode: LatencyMode
    @Binding var preferRealtime: Bool

    var body: some View {
        Section {
            Picker("Latency Mode", selection: $latencyMode) {
                ForEach(LatencyMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Toggle("Prefer Native Real-time", isOn: $preferRealtime)
        } header: {
            Text("Performance")
        } footer: {
            Text("Ultra mode minimizes latency but may reduce audio quality. Native real-time uses WebSocket for lowest latency.")
        }
    }
}
