//
//  ConsoleFilterBar.swift
//  Axon
//
//  Filter bar for developer console with search and category filter.
//

import SwiftUI

struct ConsoleFilterBar: View {
    @Binding var filterCategory: LogCategory?
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 12) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .font(.system(size: 12))

                TextField("Filter logs...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(white: 0.15))
            .cornerRadius(6)

            // Category filter
            Menu {
                Button("All Categories") {
                    filterCategory = nil
                }
                Divider()
                ForEach(LogCategoryGroup.allCases) { group in
                    Section(group.displayName) {
                        ForEach(group.categories) { category in
                            Button {
                                filterCategory = category
                            } label: {
                                HStack {
                                    Image(systemName: category.icon)
                                    Text(category.displayName)
                                    if filterCategory == category {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: filterCategory?.icon ?? "line.3.horizontal.decrease.circle")
                        .font(.system(size: 12))
                    Text(filterCategory?.displayName ?? "All")
                        .font(.system(size: 12, design: .monospaced))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(filterCategory != nil ? AppColors.signalMercury : .gray)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(white: 0.15))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(white: 0.08))
    }
}

#Preview {
    ConsoleFilterBar(
        filterCategory: .constant(nil),
        searchText: .constant("")
    )
    .background(Color.black)
}
