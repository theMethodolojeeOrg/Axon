//
//  SpeechRecognitionSection.swift
//  Axon
//
//  Speech recognition settings for Live Voice mode
//

import SwiftUI

/// Section for on-device speech recognition settings
struct SpeechRecognitionSection: View {
    @Binding var useOnDeviceSTT: Bool

    var body: some View {
        Section {
            Toggle("On-Device Speech Recognition", isOn: $useOnDeviceSTT)
        } header: {
            Text("Speech Recognition")
        } footer: {
            Text("Uses Apple's on-device speech recognition for privacy. Required for HTTP streaming providers.")
        }
    }
}
