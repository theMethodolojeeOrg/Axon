//
//  ModelTuningStatsBanner.swift
//  Axon
//
//  Stats banner showing model count and override count.
//

import SwiftUI

struct ModelTuningStatsBanner: View {
    let totalModels: Int
    let overriddenCount: Int

    var body: some View {
        HStack(spacing: 24) {
            ModelTuningStatItem(value: "\(totalModels)", label: "Models")
            ModelTuningStatItem(value: "\(overriddenCount)", label: "Overridden")
        }
        .padding()
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }
}
