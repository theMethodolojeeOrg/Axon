//
//  InternalThreadView.swift
//  Axon
//
//  UI for viewing persistent internal thread entries.
//

import SwiftUI

struct InternalThreadView: View {
    @ObservedObject private var viewModel = InternalThreadViewModel.shared

    var body: some View {
        ZStack {
            AppColors.substratePrimary
                .ignoresSafeArea()

            InternalThreadContentView()
                .environmentObject(viewModel)
        }
    }
}

struct InternalThreadContentView: View {
    @EnvironmentObject var viewModel: InternalThreadViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                InternalThreadSearchBar(text: $viewModel.searchText)
            }
            .padding(.horizontal)
            .padding(.top)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    InternalThreadFilterChip(
                        title: "All",
                        isSelected: viewModel.selectedKind == nil
                    ) {
                        viewModel.selectedKind = nil
                    }

                    ForEach(InternalThreadEntryKind.allCases) { kind in
                        InternalThreadFilterChip(
                            title: kind.displayName,
                            icon: kind.icon,
                            isSelected: viewModel.selectedKind == kind
                        ) {
                            viewModel.selectedKind = kind
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            Toggle(isOn: $viewModel.includeAIOnly) {
                Text("Include AI-only entries")
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)
            }
            .tint(AppColors.signalMercury)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if viewModel.filteredEntries.isEmpty {
                InternalThreadEmptyState()
            } else {
                List {
                    ForEach(viewModel.filteredEntries) { entry in
                        InternalThreadEntryRow(entry: entry)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    viewModel.reload()
                }
            }
        }
    }
}

struct InternalThreadEntryRow: View {
    let entry: InternalThreadEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.kind.icon)
                .font(.system(size: 18))
                .foregroundColor(AppColors.signalMercury)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.kind.displayName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    if entry.visibility == .aiOnly {
                        Text("AI Only")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.substrateSecondary)
                            .cornerRadius(6)
                    }

                    Spacer()

                    Text(entry.timestamp, style: .relative)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }

                Text(entry.content)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(4)

                if !entry.tags.isEmpty {
                    Text(entry.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalMercury)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.substrateSecondary)
        )
    }
}

struct InternalThreadSearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textSecondary)

            TextField("Search internal thread...", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .padding(12)
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
    }
}

struct InternalThreadFilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(AppTypography.labelSmall())
                }
                Text(title)
                    .font(AppTypography.labelMedium())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? AppColors.signalMercury : AppColors.substrateSecondary)
            .foregroundColor(isSelected ? .white : AppColors.textSecondary)
            .cornerRadius(20)
        }
    }
}

struct InternalThreadEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)

            Text("No Internal Thread Entries")
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textSecondary)

            Text("Heartbeat updates and internal notes will appear here.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
}

#Preview {
    InternalThreadView()
}
