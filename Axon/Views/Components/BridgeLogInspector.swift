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
            // Log List
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    SearchField(text: $searchText, placeholder: "Filter logs...")
                    
                    Menu {
                        Toggle("Incoming", isOn: $logService.showIncoming)
                        Toggle("Outgoing", isOn: $logService.showOutgoing)
                        Divider()
                        Toggle("Requests", isOn: $logService.showRequests)
                        Toggle("Responses", isOn: $logService.showResponses)
                        Toggle("Notifications", isOn: $logService.showNotifications)
                        Toggle("Errors", isOn: $logService.showErrors)
                        Divider()
                        Toggle("Only Invalid", isOn: $logService.onlyShowInvalid)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundColor(logService.filteredEntries.count != logService.entries.count ? AppColors.accentPrimary : AppColors.textSecondary)
                    }
                    
                    Button(action: { logService.clear() }) {
                        Image(systemName: "trash")
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(12)
                .background(AppColors.substrateSecondary)
                .onChange(of: searchText) { newValue in
                    logService.filterText = newValue
                }
                
                Divider()
                
                // List
                ScrollViewReader { proxy in
                    List(selection: $selectedEntry) {
                        ForEach(logService.filteredEntries) { entry in
                            LogEntryRow(entry: entry)
                                .tag(entry)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(selectedEntry == entry ? AppColors.substrateTertiary : Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: logService.entries.count) { _ in
                        // Auto-scroll to top if at top? No, logs are newest first.
                    }
                }
            }
            .frame(minWidth: 300)
            
            Divider()
            
            // Detail View
            if let entry = selectedEntry {
                LogDetailView(entry: entry)
                    .frame(minWidth: 400)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.left.arrow.right.circle")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.substrateTertiary)
                    Text("Select a log entry to view details")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.substratePrimary)
            }
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

struct LogEntryRow: View {
    let entry: BridgeLogEntry
    
    var body: some View {
        HStack(spacing: 12) {
            // Direction & Type Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 28, height: 28)
                
                Image(systemName: entry.messageType.icon)
                    .font(.system(size: 14))
                    .foregroundColor(statusColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.direction == .outgoing ? "To VS Code" : "From VS Code")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                    
                    Spacer()
                    
                    Text(entry.formattedTimestamp)
                        .font(AppTypography.labelSmall(.monospaced))
                        .foregroundColor(AppColors.textTertiary)
                }
                
                Text(entry.summary)
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    var statusColor: Color {
        if !entry.isValid || entry.messageType == .error {
            return AppColors.accentError
        }
        switch entry.messageType {
        case .request: return AppColors.accentPrimary
        case .response: return AppColors.accentSuccess
        case .notification: return AppColors.accentWarning
        default: return AppColors.textSecondary
        }
    }
}

struct LogDetailView: View {
    let entry: BridgeLogEntry
    @State private var showRaw = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.messageType.rawValue.uppercased())
                        .font(AppTypography.labelSmall(.bold))
                        .foregroundColor(AppColors.textSecondary)
                    
                    Text(entry.summary)
                        .font(AppTypography.headerSmall())
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
            .background(AppColors.substrateSecondary)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Metadata
                    HStack(spacing: 24) {
                        DetailField(label: "Time", value: entry.formattedTimestamp)
                        DetailField(label: "Direction", value: entry.direction.label)
                        if let id = entry.requestId {
                            DetailField(label: "Request ID", value: id)
                        }
                    }
                    
                    if !entry.isValid {
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
                    
                    // JSON
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
                            .background(AppColors.substrateSecondary)
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .background(AppColors.substratePrimary)
    }
}

struct DetailField: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
            Text(value)
                .font(AppTypography.bodySmall(.medium))
                .foregroundColor(AppColors.textPrimary)
        }
    }
}
