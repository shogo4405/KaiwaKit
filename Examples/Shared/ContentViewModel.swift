import AVFoundation
import KaiwaKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

@MainActor
final class ContentViewModel: ObservableObject {
    enum CredentialKind: String, CaseIterable, Identifiable {
        case apiKey, shortLivedToken
        var id: String { rawValue }
        func label(_ provider: ConversationProvider) -> String {
            self == .apiKey ? "API key (local development)" : (provider == .openAI ? "Realtime client secret" : "Ephemeral token")
        }
    }
    @Published private(set) var state: ConversationState = .idle
    @Published private(set) var lines = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var muted = false
    @Published var provider = ConversationProvider.openAI {
        didSet { if oldValue != provider { credential = ""; credentialKind = .apiKey } }
    }
    @Published var model = GeminiSessionConfiguration.defaultModel
    @Published var credentialKind = CredentialKind.apiKey {
        didSet { if oldValue != credentialKind { credential = "" } }
    }
    @Published var credential = ""
    var active: Bool { state == .connecting || state == .connected || state == .closing }
    var canConnect: Bool { !active && !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (provider != .gemini || !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    var apiKeysURL: URL { URL(string: provider == .openAI ? "https://platform.openai.com/api-keys" : "https://aistudio.google.com/apikey")! }
    var status: String {
        switch state {
        case .idle, .closed: "Disconnected"
        case .connecting: "Connecting…"
        case .connected: "Listening to \(provider.name)"
        case .closing: "Disconnecting…"
        }
    }
    private var session: (any ConversationSession)?
    private var callTask: Task<Void, Never>?
    func connect() {
        guard canConnect else { return }
        errorMessage = nil; muted = false; lines = ""; state = .connecting
        let value = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedProvider = provider
        let selectedKind = credentialKind
        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        callTask = Task {
            var conversation: (any ConversationSession)?
            do {
                guard await AVCaptureDevice.requestAccess(for: .audio) else { throw CallError.microphonePermission }
                try Task.checkCancellation()
                #if os(iOS)
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
                try audioSession.setActive(true)
                UIApplication.shared.isIdleTimerDisabled = true
                #endif
                let current: any ConversationSession
                switch selectedProvider {
                case .openAI:
                    current = OpenAIConversationSession(configuration: RealtimeSessionConfiguration(
                        apiKey: selectedKind == .apiKey ? value : nil,
                        clientSecret: selectedKind == .shortLivedToken ? value : nil))
                case .gemini:
                    current = GeminiConversationSession(configuration: GeminiSessionConfiguration(
                        credential: selectedKind == .apiKey ? .apiKey(value) : .ephemeralToken(value), model: selectedModel))
                }
                conversation = current; session = current
                let events = current.events
                try await current.connect()
                try Task.checkCancellation()
                state = .connected
                for try await event in events {
                    try Task.checkCancellation()
                    if case .transcript(let speaker, let text, let isFinal) = event, isFinal {
                        lines = String((lines + "\(speaker == .user ? "You" : selectedProvider.name): \(text)\n\n").suffix(32_000))
                    }
                }
            } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
            state = .closing
            await conversation?.close()
            session = nil
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
            state = .closed; muted = false; callTask = nil
        }
    }
    func toggleMute() {
        muted.toggle()
        let enabled = !muted
        Task { await session?.setMicrophoneEnabled(enabled) }
    }
    func close() { guard callTask != nil else { return }; state = .closing; callTask?.cancel(); Task { await session?.close() } }
    private enum CallError: LocalizedError {
        case microphonePermission
        var errorDescription: String? { "Allow microphone access in System Settings to start a voice conversation." }
    }
}
