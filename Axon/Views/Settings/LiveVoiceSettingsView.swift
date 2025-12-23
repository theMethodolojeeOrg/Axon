import SwiftUI

struct LiveVoiceSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section(header: Text("Default Provider")) {
                Picker("Provider", selection: $viewModel.settings.liveSettings.defaultProvider) {
                    Text("Gemini Live").tag(AIProvider.gemini)
                    Text("OpenAI Realtime").tag(AIProvider.openai)
                }
            }

            Section(header: Text("Model Configuration")) {
                HStack {
                    Text("Model ID")
                    Spacer()
                    TextField("Model ID", text: $viewModel.settings.liveSettings.defaultModelId)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 200)
                }
            }

            Section(header: Text("Voices")) {
                Picker("OpenAI Voice", selection: $viewModel.settings.liveSettings.openAIVoice) {
                    Text("Alloy").tag("alloy")
                    Text("Ash").tag("ash")
                    Text("Ballad").tag("ballad")
                    Text("Coral").tag("coral")
                    Text("Echo").tag("echo")
                    Text("Sage").tag("sage")
                    Text("Shimmer").tag("shimmer")
                    Text("Verse").tag("verse")
                    Text("Marin").tag("marin")
                }

                Picker("Gemini Voice", selection: $viewModel.settings.liveSettings.geminiVoice) {
                    Text("Kore").tag("Kore")
                    Text("Leda").tag("Leda")
                    Text("Puck").tag("Puck")
                    Text("Charon").tag("Charon")
                    Text("Fenrir").tag("Fenrir")
                    Text("Orus").tag("Orus")
                    Text("Aoede").tag("Aoede")
                    Text("Callirrhoe").tag("Callirrhoe")
                    Text("Zenir").tag("Zenir")
                }
            }
        }
        .navigationTitle("Realtime Voice")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
