import SwiftUI
import Foundation

struct ArchivedConversationsSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var archived: [SettingsStorage.ArchivedEntry] = []
    @State private var isPurging = false

    private let storage = SettingsStorage.shared
    @StateObject private var conversationService = ConversationService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Archived Conversations") {
                VStack(spacing: 0) {
                    if archived.isEmpty {
                        HStack {
                            Image(systemName: "archivebox")
                                .foregroundColor(AppColors.textTertiary)
                            Text("No archived conversations")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                            Spacer()
                        }
                        .padding()
                    } else {
                        ForEach(archived, id: \.id) { entry in
                            HStack(spacing: 12) {
                                Image(systemName: "bubble.left.fill")
                                    .foregroundColor(AppColors.textTertiary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(resolvedTitle(for: entry.id))
                                        .font(AppTypography.bodyMedium(.medium))
                                        .foregroundColor(AppColors.textPrimary)

                                    Text("Archived \(entry.archivedAt, style: .relative)")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.textTertiary)
                                }

                                Spacer()

                                Menu {
                                    Button("Restore") {
                                        storage.unarchiveConversation(id: entry.id)
                                        reload()
                                    }
                                    Button(role: .destructive) {
                                        Task {
                                            do {
                                                try await conversationService.deleteConversation(id: entry.id)
                                            } catch {
                                                print("[Archive] Delete failed: \(error)")
                                            }
                                            storage.unarchiveConversation(id: entry.id)
                                            storage.setDisplayName(nil, for: entry.id)
                                            storage.setGeneratedTitle(nil, for: entry.id)
                                            reload()
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle.fill")
                                        .foregroundColor(AppColors.textSecondary)
                                        .font(.system(size: 22))
                                }
                            }
                            .padding()
                            .background(AppColors.substrateSecondary)
                            .overlay(
                                Rectangle()
                                    .fill(AppColors.glassBorder)
                                    .frame(height: 1)
                                    .opacity(0.5), alignment: .bottom
                            )
                        }
                    }
                }
            }

            SettingsSection(title: "Retention") {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 32)
                        Text("Retention Period")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Stepper(value: Binding(
                            get: { viewModel.settings.archiveRetentionDays },
                            set: { newValue in
                                Task { await viewModel.updateSetting(\.archiveRetentionDays, max(5, min(365, newValue))) }
                            }
                        ), in: 5...365) {
                            Text("\(viewModel.settings.archiveRetentionDays) days")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .labelsHidden()
                    }
                    .padding()
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)

                    Button(action: purgeNow) {
                        HStack {
                            if isPurging { ProgressView().tint(.white) }
                            Text("Purge Now")
                                .font(AppTypography.titleMedium())
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColors.signalMercury)
                        .cornerRadius(12)
                    }
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        archived = storage.archivedEntries().sorted { $0.archivedAt > $1.archivedAt }
    }

    private func purgeNow() {
        isPurging = true
        let days = viewModel.settings.archiveRetentionDays
        storage.purgeExpiredArchived(retentionDays: days)
        reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isPurging = false }
    }

    private func conversationTitle(for id: String) -> String? {
        if let conv = conversationService.conversations.first(where: { $0.id == id }) {
            return conv.title
        }
        return nil
    }

    private func resolvedTitle(for id: String) -> String {
        if let persisted = conversationTitle(for: id) {
            return storage.resolvedConversationTitle(conversationId: id, persistedTitle: persisted)
        }

        if let manual = storage.displayName(for: id) {
            return manual
        }

        if let generated = storage.generatedTitle(for: id) {
            return generated
        }

        return id
    }
}

#Preview {
    ScrollView {
        ArchivedConversationsSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}
