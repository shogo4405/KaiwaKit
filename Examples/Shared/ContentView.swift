import SwiftUI

struct ContentView: View {
    @StateObject private var model = ContentViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("KaiwaKit")
                .font(.largeTitle.bold())
            Text("Talk with OpenAI over WebRTC. Responses use an AI-generated voice.")
                .foregroundStyle(.secondary)

            GroupBox("OpenAI connection") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Credential", selection: $model.credentialKind) {
                        ForEach(ContentViewModel.CredentialKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    SecureField("Enter your credential", text: $model.credential)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Text("Credentials stay in memory. API usage is billed separately from ChatGPT.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Open OpenAI API keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    DisclosureGroup("About ChatGPT sign-in") {
                        Text("The documented ChatGPT sign-in flow supports the Responses API. Realtime access through that flow is not confirmed. This sample uses an API key or a short-lived Realtime client secret.")
                            .font(.caption)
                    }
                }
                .padding(4)
                .disabled(model.readyState != .closed)
            }

            HStack {
                Label(model.status, systemImage: model.readyState == .open ? "mic.fill" : "mic.slash")
                Spacer()
                if model.readyState == .closed {
                    Button("Start conversation") { model.connect() }
                        .disabled(!model.canConnect)
                        .buttonStyle(.borderedProminent)
                } else {
                    if model.readyState == .connecting || model.readyState == .closing {
                        ProgressView().controlSize(.small)
                    }
                    Button("Stop") { model.close() }
                        .disabled(model.readyState == .closing)
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
