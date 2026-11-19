import Foundation

/// A Gemini Live voice session. The host grants microphone permission and configures its audio route.
@MainActor
public final class GeminiConversationSession: ConversationSession {
    public private(set) var state: ConversationState = .idle
    public var events: AsyncThrowingStream<ConversationEvent, any Error> { output.stream }
    private let configuration: GeminiSessionConfiguration
    private let socket: any GeminiSocket
    private let audio: any GeminiAudio
    private let output = ConversationEvents()
    private var receiver: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var ready: AsyncThrowingStream<Bool, any Error>.Continuation?
    private var pendingMessages: [GeminiWire.Message] = []
    private var inputText = ""
    private var outputText = ""

    public convenience init(configuration: GeminiSessionConfiguration) {
        self.init(configuration: configuration, socket: URLSessionGeminiSocket(), audio: AppleGeminiAudio())
    }
    init(configuration: GeminiSessionConfiguration, socket: any GeminiSocket, audio: any GeminiAudio) {
        self.configuration = configuration; self.socket = socket; self.audio = audio
    }
    public func connect() async throws {
        guard state == .idle else { throw ConversationError.closed }
        state = .connecting
        let readiness = AsyncThrowingStream<Bool, any Error>(bufferingPolicy: .bufferingOldest(1)) { ready = $0 }
        do {
            try await socket.open(GeminiWire.url(configuration.credential))
            guard state == .connecting else { throw ConversationError.closed }
            receiver = Task { [weak self] in
                guard let self else { return }
                do {
                    while !Task.isCancelled {
                        let message = try GeminiWire.decode(await socket.receive())
                        guard state == .connecting || state == .connected else { return }
                        if message.setupComplete { ready?.yield(true); ready?.finish() }
                        if state == .connecting {
                            guard pendingMessages.count < 64 else { throw ConversationError.overflow }
                            pendingMessages.append(message)
                        } else { try handle(message) }
                    }
                } catch {
                    guard !Task.isCancelled, state != .closed else { return }
                    ready?.finish(throwing: error)
                    output.finish(error)
                    await close()
                }
            }
            try await socket.send(GeminiWire.setup(configuration.model))
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    var iterator = readiness.makeAsyncIterator()
                    guard try await iterator.next() != nil else { throw ConversationError.closed }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    throw ConversationError.timeout
                }
                defer { group.cancelAll() }
                try await group.next()
            }
            try Task.checkCancellation()
            guard state == .connecting else { throw ConversationError.closed }
            let capture = try audio.start()
            sender = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await bytes in capture {
                        try Task.checkCancellation()
                        try await socket.send(GeminiWire.audio(bytes))
                    }
                } catch {
                    guard !Task.isCancelled, state != .closed else { return }
                    output.finish(error)
                    await close()
                }
            }
            state = .connected
            for message in pendingMessages { try handle(message) }
            pendingMessages.removeAll()
        } catch { output.finish(error); await close(); throw error }
    }
    public func setMicrophoneEnabled(_ enabled: Bool) async { audio.setMicrophoneEnabled(enabled) }
    public func close() async {
        guard state != .closed else { return }
        state = .closing
        ready?.finish(throwing: ConversationError.closed)
        receiver?.cancel(); sender?.cancel()
        receiver = nil; sender = nil
        socket.close(); audio.close()
        pendingMessages.removeAll()
        output.finish()
        state = .closed
    }
    private func handle(_ message: GeminiWire.Message) throws {
        if message.interrupted { audio.interrupt(); try output.emit(.interrupted) }
        else { for bytes in message.audio { try audio.play(bytes) } }
        if let text = message.input { guard inputText.utf8.count + text.utf8.count <= 65536 else { throw ConversationError.overflow }; inputText += text; try output.emit(.transcript(speaker: .user, text: inputText, isFinal: false)) }
        if let text = message.output { guard outputText.utf8.count + text.utf8.count <= 65536 else { throw ConversationError.overflow }; outputText += text; try output.emit(.transcript(speaker: .assistant, text: outputText, isFinal: false)) }
        if message.inputFinished || message.turnComplete || message.interrupted {
            if !inputText.isEmpty { try output.emit(.transcript(speaker: .user, text: inputText, isFinal: true)) }
            inputText = ""
        }
        if message.outputFinished || message.turnComplete || message.interrupted {
            if !outputText.isEmpty { try output.emit(.transcript(speaker: .assistant, text: outputText, isFinal: true)) }
            outputText = ""
        }
    }
}
