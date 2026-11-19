@preconcurrency import AVFoundation
import HaishinKit
import Foundation

/// OpenAI's existing WebRTC session behind the provider-independent voice API.
@MainActor
public final class OpenAIConversationSession: ConversationSession {
    public private(set) var state: ConversationState = .idle
    public var events: AsyncThrowingStream<ConversationEvent, any Error> { output.stream }
    private let configuration: RealtimeSessionConfiguration
    private let mixer = MediaMixer(captureSessionMode: .single)
    private let player = AudioPlayer(audioEngine: AVAudioEngine())
    private let output = ConversationEvents()
    private var session: RealtimeSession?
    private var forwarding: Task<Void, Never>?
    private var microphoneEnabled = true

    public init(configuration: RealtimeSessionConfiguration) { self.configuration = configuration }
    public func connect() async throws {
        guard state == .idle else { throw ConversationError.closed }
        state = .connecting
        let current = RealtimeSession(uri: URL(string: "https://api.openai.com/v1/realtime/calls")!, mode: .publish, configuration: configuration)
        session = current
        let stream = await current.stream
        do {
            guard let microphone = AVCaptureDevice.default(for: .audio) else { throw ConversationError.audio }
            try await mixer.attachAudio(microphone)
            await stream.attachAudioPlayer(player)
            await mixer.addOutput(stream)
            let events = await current.events
            forwarding = Task { [weak self] in
                guard let self else { return }
                do {
                    for await event in events {
                        if Task.isCancelled { return }
                        switch event.type {
                        case "response.output_audio_transcript.done":
                            if let text = event.transcript { try output.emit(.transcript(speaker: .assistant, text: text, isFinal: true)) }
                        case "conversation.item.input_audio_transcription.completed":
                            if let text = event.transcript { try output.emit(.transcript(speaker: .user, text: text, isFinal: true)) }
                        case "input_audio_buffer.speech_started": try output.emit(.interrupted)
                        case "error": throw ConversationError.connection
                        default: break
                        }
                    }
                } catch { output.finish(error); await close() }
            }
            try Task.checkCancellation()
            guard state == .connecting else { throw ConversationError.closed }
            try await current.connect { [weak self] in
                Task { @MainActor in
                    guard let self, self.state != .closed else { return }
                    self.output.finish(ConversationError.connection)
                    await self.close()
                }
            }
            let deadline = Date().addingTimeInterval(30)
            while !(await current.connected) {
                try Task.checkCancellation()
                guard state == .connecting, Date() < deadline else { throw ConversationError.timeout }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            try Task.checkCancellation()
            guard state == .connecting else { throw ConversationError.closed }
            await setMicrophoneEnabled(microphoneEnabled)
            await mixer.startRunning()
            try Task.checkCancellation()
            guard state == .connecting else { throw ConversationError.closed }
            state = .connected
        } catch {
            output.finish(error)
            await cleanup()
            state = .closed
            throw error
        }
    }
    public func setMicrophoneEnabled(_ enabled: Bool) async {
        microphoneEnabled = enabled
        var settings = await mixer.audioMixerSettings
        settings.isMuted = !enabled
        await mixer.setAudioMixerSettings(settings)
    }
    public func close() async {
        guard state != .closed && state != .closing else { return }
        state = .closing
        await cleanup()
        state = .closed
    }
    private func cleanup() async {
        forwarding?.cancel(); forwarding = nil
        await mixer.stopRunning()
        if let session {
            let stream = await session.stream
            await mixer.removeOutput(stream)
            try? await mixer.attachAudio(nil)
            try? await session.close()
            await stream.attachAudioPlayer(nil)
        }
        session = nil
        output.finish()
    }
}
