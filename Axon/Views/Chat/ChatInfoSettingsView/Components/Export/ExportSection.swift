//
//  ExportSection.swift
//  Axon
//
//  Export options section for ChatInfoSettingsView
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ExportSection: View {
    let conversation: Conversation
    
    @State private var isExporting = false
    @State private var exportErrorMessage: String? = nil
    @State private var exportedFileURL: URL? = nil
    @State private var exportedShareItems: [Any] = []
    
    #if !os(macOS)
    @State private var showingIOSShareSheet = false
    #endif
    
    var body: some View {
        ChatInfoSection(title: "Export") {
            VStack(spacing: 12) {
                ExportButtonRow(
                    title: "Export JSON",
                    subtitle: "Full thread + metadata",
                    systemImage: "doc.text",
                    isExporting: isExporting
                ) {
                    Task { await exportAndShare(format: .json) }
                }
                
                ExportButtonRow(
                    title: "Export Markdown",
                    subtitle: "Readable transcript",
                    systemImage: "doc.plaintext",
                    isExporting: isExporting
                ) {
                    Task { await exportAndShare(format: .markdown) }
                }
                
                ExportButtonRow(
                    title: "Export ZIP",
                    subtitle: "JSON + MD + attachment payloads (when available)",
                    systemImage: "archivebox",
                    isExporting: isExporting
                ) {
                    Task { await exportAndShare(format: .zip) }
                }
                
                ExportButtonRow(
                    title: "Session Audio (Cached)",
                    subtitle: "TTS audio stored on this device",
                    systemImage: "waveform",
                    isExporting: isExporting
                ) {
                    Task { await exportAndShare(format: .sessionAudioCached) }
                }
                
                ExportButtonRow(
                    title: "Session Audio (All)",
                    subtitle: "Includes CloudKit audio when available",
                    systemImage: "waveform.and.arrow.down",
                    isExporting: isExporting
                ) {
                    Task { await exportAndShare(format: .sessionAudioAll) }
                }
                
                if let exportErrorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.accentError)
                        
                        Text(exportErrorMessage)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.accentError)
                            .lineLimit(3)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColors.accentError.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showingIOSShareSheet) {
            if let exportedFileURL {
                ActivityView(activityItems: [exportedFileURL])
            } else {
                EmptyView()
            }
        }
        #endif
        #if os(macOS)
        .background(
            MacSharePicker(items: exportedShareItems)
                .frame(width: 0, height: 0)
        )
        #endif
    }
    
    // MARK: - Export Logic
    
    @MainActor
    private func exportAndShare(format: ChatExportService.ExportFormat) async {
        exportErrorMessage = nil
        isExporting = true
        defer { isExporting = false }
        
        do {
            let exported = try await ChatExportService.shared.exportFile(for: conversation, format: format)
            exportedFileURL = exported.url
            
            #if os(macOS)
            // macOS: offer both Save As… and Share.
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = exported.suggestedFilename
            panel.allowedFileTypes = [exported.url.pathExtension]
            
            panel.begin { response in
                guard response == .OK, let destination = panel.url else { return }
                do {
                    try FileManager.default.copyItem(at: exported.url, to: destination)
                } catch {
                    // If file exists, overwrite
                    do {
                        try? FileManager.default.removeItem(at: destination)
                        try FileManager.default.copyItem(at: exported.url, to: destination)
                    } catch {
                        exportErrorMessage = error.localizedDescription
                    }
                }
                
                // Share picker (shares the saved file if we have it, else temp file)
                exportedShareItems = [destination]
            }
            #else
            // iOS: share sheet
            showingIOSShareSheet = true
            #endif
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ExportSection(conversation: Conversation(
        userId: "user1",
        title: "Test Conversation",
        projectId: "default",
        messageCount: 10
    ))
    .padding()
    .background(AppSurfaces.color(.contentBackground))
}
