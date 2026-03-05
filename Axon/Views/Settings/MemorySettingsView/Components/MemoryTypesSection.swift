//
//  MemoryTypesSection.swift
//  Axon
//
//  Memory types information section
//

import SwiftUI

struct MemoryTypesSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsSection(title: "Memory Types") {
            VStack(spacing: 12) {
                MemoryTypeInfo(
                    icon: "person.fill",
                    title: "Allocentric",
                    description: "Knowledge about you: preferences, facts, relationships, context",
                    color: AppColors.signalMercury
                )

                MemoryTypeInfo(
                    icon: "brain.head.profile",
                    title: "Egoic",
                    description: "What works for Axon: procedures, insights, learnings",
                    color: AppColors.signalLichen
                )
            }
        }
    }
}
