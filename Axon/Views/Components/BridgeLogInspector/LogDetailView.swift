import SwiftUI

struct LogDetailView: View {
    let entry: BridgeLogEntry
    @State private var showRaw = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadata

                    if !entry.isValid {
                        validationErrors
                    }

                    payload
                }
                .padding()
            }
        }
        .background(AppSurfaces.color(.contentBackground))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.messageType.rawValue.uppercased())
                    .font(AppTypography.labelSmall(.bold))
                    .foregroundColor(AppColors.textSecondary)

                Text(entry.summary)
                    .font(AppTypography.headlineSmall())
                    .foregroundColor(AppColors.textPrimary)
            }

            Spacer()

            Picker("Format", selection: $showRaw) {
                Text("Pretty").tag(false)
                Text("Raw").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
        .padding()
        .background(AppSurfaces.color(.cardBackground))
    }

    private var metadata: some View {
        HStack(spacing: 24) {
            DetailField(label: "Time", value: entry.formattedTimestamp)
            DetailField(label: "Direction", value: entry.direction.label)
            if let id = entry.requestId {
                DetailField(label: "Request ID", value: id)
            }
        }
    }

    private var validationErrors: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Validation Errors")
                .font(AppTypography.labelSmall(.bold))
                .foregroundColor(AppColors.accentError)

            ForEach(entry.validationErrors, id: \.self) { error in
                Text("• \(error)")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.accentError)
            }
        }
        .padding()
        .background(AppColors.accentError.opacity(0.1))
        .cornerRadius(8)
    }

    private var payload: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Payload")
                    .font(AppTypography.labelSmall(.bold))
                    .foregroundColor(AppColors.textSecondary)

                Spacer()

                Button(action: {
                    AppClipboard.copy(showRaw ? entry.rawJSON : entry.prettyJSON)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            Text(showRaw ? entry.rawJSON : entry.prettyJSON)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(AppColors.textPrimary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)
        }
    }
}
