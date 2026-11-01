import AVFoundation
import HaishinKit
import KaiwaKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

@MainActor
final class ContentViewModel: ObservableObject {
    enum CredentialKind: String, CaseIterable, Identifiable {
        case apiKey = "API key (local development)"
        case clientSecret = "Realtime client secret"
        var id: String { rawValue }
    }

    @Published private(set) var readyState: StreamSessionReadyState = .closed
    @Published private(set) var lines = ""
    @Published private(set) var errorMessage: String?
    @Published var credentialKind = CredentialKind.apiKey
    @Published var credential = ""

    var canConnect: Bool {
        readyState == .closed && !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var status: String {
        switch readyState {
        case .closed: "Disconnected"
        case .connecting: "Connecting…"
        case .open: "Listening"
        case .closing: "Disconnecting…"
        }
    }

    private let mixer = MediaMixer(captureSessionMode: .single)
    private let audioPlayer = AudioPlayer(audioEngine: AVAudioEngine())
    private var callTask: Task<Void, Never>?

    func connect() {
        guard canConnect else { return }
        errorMessage = nil
        readyState = .connecting
        let value = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuration = RealtimeSessionConfiguration(
            apiKey: credentialKind == .apiKey ? value : nil,
            clientSecret: credentialKind == .clientSecret ? value : nil
        )
        callTask = Task {
            let session = RealtimeSession(
                uri: URL(string: "https://api.openai.com/v1/realtime/calls")!,
                mode: .publish,
                configuration: configuration
            )
            let stream = await session.stream
            do {
                guard await AVCaptureDevice.requestAccess(for: .audio) else {
                    throw CallError.microphonePermission
                }
                try Task.checkCancellation()
                guard let microphone = AVCaptureDevice.default(for: .audio) else {
                    throw CallError.noMicrophone
                }
                #if os(iOS)
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
                try audioSession.setActive(true)
                UIApplication.shared.isIdleTimerDisabled = true
                #endif
                try await mixer.attachAudio(microphone)
                await stream.attachAudioPlayer(audioPlayer)
                await mixer.addOutput(stream)
                let events = await session.events
                try Task.checkCancellation()
                try await session.connect { [weak self] in
                    Task { @MainActor in
                        self?.errorMessage = "The Realtime connection was closed. Please reconnect."
                        self?.close()
                    }
                }
                try Task.checkCancellation()
                await mixer.startRunning()
                try Task.checkCancellation()
                readyState = .open
                for await event in events {
                    guard !Task.isCancelled else { break }
                    if event.type == "error" {
                        errorMessage = event.error?.message ?? "OpenAI reported a Realtime error."
                        break
                    }
                    if event.type == "response.output_audio_transcript.done", let transcript = event.transcript {
                        lines += "AI: \(transcript)\n\n"
                    } else if event.type == "response.output_item.done", let item = event.item {
                        // Audio transcripts are already displayed by the event above.
                        for content in item.content where content.type == "output_text" {
                            if let text = content.text { lines += "AI: \(text)\n\n" }
                        }
                    }
                }
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
            readyState = .closing
            await mixer.stopRunning()
            await mixer.removeOutput(stream)
            try? await mixer.attachAudio(nil)
            try? await session.close()
            await stream.attachAudioPlayer(nil)
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
            readyState = .closed
            callTask = nil
        }
    }

    func close() {
        guard callTask != nil else { return }
        readyState = .closing
        callTask?.cancel()
    }

    private enum CallError: LocalizedError {
        case microphonePermission
        case noMicrophone

        var errorDescription: String? {
            switch self {
            case .microphonePermission: "Allow microphone access in System Settings to start a voice conversation."
            case .noMicrophone: "No microphone is available. Connect a microphone and try again."
            }
        }
    }
}
