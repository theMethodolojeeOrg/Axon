//
//  TranscriptionTestSection.swift
//  Axon
//
//  Speech recognition test section
//

import SwiftUI

/// Section for testing Apple's on-device speech recognition
struct TranscriptionTestSection: View {
    @ObservedObject var transcriptionTestController: TranscriptionTestController

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Test Transcription")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button(action: {
                        if transcriptionTestController.isListening {
                            transcriptionTestController.stopListening()
                        } else {
                            transcriptionTestController.startListening()
                        }
                    }) {
                        Image(systemName: transcriptionTestController.isListening ? "stop.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(transcriptionTestController.isListening ? Color.red : Color.accentColor))
                    }
                    .buttonStyle(.plain)
                }

                // Transcript display
                if !transcriptionTestController.transcript.isEmpty || transcriptionTestController.isListening {
                    Text(transcriptionTestController.transcript.isEmpty ? "Listening..." : transcriptionTestController.transcript)
                        .font(.body)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        #if os(macOS)
                        .background(Color(NSColor.controlBackgroundColor))
                        #else
                        .background(Color(.secondarySystemBackground))
                        #endif
                        .cornerRadius(8)
                        .foregroundColor(transcriptionTestController.transcript.isEmpty ? .secondary : .primary)
                }

                // Mic level indicator when listening
                if transcriptionTestController.isListening {
                    HStack(spacing: 4) {
                        ForEach(0..<10, id: \.self) { index in
                            Capsule()
                                .fill(index < Int(transcriptionTestController.audioLevel * 10) ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 4, height: 16)
                        }
                    }
                }
            }
        } header: {
            Text("Speech Recognition Test")
        } footer: {
            Text("Test how your voice is transcribed using Apple's on-device speech recognition.")
        }
    }
}
