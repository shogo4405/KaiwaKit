import SwiftUI
import KaiwaKit

struct ContentView: View {
    @StateObject private var model = ContentViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("KaiwaKit")
                .font(.largeTitle.bold())
            Text("Talk with OpenAI or Gemini. Responses use an AI-generated voice.")
                .foregroundStyle(.secondary)

            GroupBox("AI connection") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Service", selection: $model.provider) {
                        ForEach(ConversationProvider.allCases) { provider in Text(provider.name).tag(provider) }
                    }
                    if model.provider == .gemini {
                        TextField("Gemini Live model", text: $model.model).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    }
                    Picker("Credential", selection: $model.credentialKind) {
                        ForEach(ContentViewModel.CredentialKind.allCases) { kind in
                            Text(kind.label(model.provider)).tag(kind)
                        }
                    }
                    SecureField("Enter your credential", text: $model.credential)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Text("Credentials stay in memory. Provider API usage charges apply.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Open \(model.provider.name) API keys", destination: model.apiKeysURL)
                    if model.provider == .openAI {
                        DisclosureGroup("About ChatGPT sign-in") {
                        Text("The documented ChatGPT sign-in flow supports the Responses API. Realtime access through that flow is not confirmed. This sample uses an API key or a short-lived Realtime client secret.")
                            .font(.caption)
                        }
                    }
                }
                .padding(4)
                .disabled(model.active)
            }

            HStack {
                Label(model.status, systemImage: model.state == .connected ? "mic.fill" : "mic.slash")
                Spacer()
                if !model.active {
                    Button("Start conversation") { model.connect() }
                        .disabled(!model.canConnect)
                        .buttonStyle(.borderedProminent)
                } else {
                    if model.state == .connecting || model.state == .closing {
                        ProgressView().controlSize(.small)
                    }
                    Button(model.muted ? "Unmute" : "Mute") { model.toggleMute() }
                        .disabled(model.state != .connected)
                    Button("Stop") { model.close() }
                        .disabled(model.state == .closing)
                }
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage).foregroundStyle(.red).textSelection(.enabled)
            }
            ScrollView {
                Text(model.lines.isEmpty ? "The assistant’s transcript will appear here." : model.lines)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { phase in
            if phase == .background { model.close() }
        }
    }
}
