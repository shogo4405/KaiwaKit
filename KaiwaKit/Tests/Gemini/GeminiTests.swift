import Foundation
import Testing
@testable import KaiwaKit

@Suite struct GeminiTests {
    @Test func credentialUsesCorrectEndpointAndEscapesQuery() throws {
        let key = try GeminiWire.url(.apiKey(" key+&?/ "))
        let token = try GeminiWire.url(.ephemeralToken("token+&?/"))
        #expect(key.host == "generativelanguage.googleapis.com")
        #expect(key.path.hasSuffix(".BidiGenerateContent"))
        #expect(URLComponents(url: key, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "key+&?/")
        #expect(key.absoluteString.contains("%2B"))
        #expect(token.path.hasSuffix("BidiGenerateContentConstrained"))
        #expect(URLComponents(url: token, resolvingAgainstBaseURL: false)?.queryItems?.first?.name == "access_token")
        #expect(throws: (any Error).self) { try GeminiWire.url(.apiKey(" \n")) }
    }
    @Test func setupAndPcmEnvelope() throws {
        let root = try #require(JSONSerialization.jsonObject(with: Data(GeminiWire.setup("test-model").utf8)) as? [String: Any])
        let setup = try #require(root["setup"] as? [String: Any])
        #expect(setup["model"] as? String == "models/test-model")
        #expect(setup["inputAudioTranscription"] != nil)
        #expect(setup["outputAudioTranscription"] != nil)
        let config = try #require(setup["generationConfig"] as? [String: Any])
        #expect(config["responseModalities"] as? [String] == ["AUDIO"])
        let audio = try #require(JSONSerialization.jsonObject(with: Data(GeminiWire.audio(Data([1, 2])).utf8)) as? [String: Any])
        #expect(String(describing: audio).contains("audio/pcm;rate=16000"))
    }
    @Test func receivesAllPartsAndTranscriptsInSameMessage() throws {
        let message = try GeminiWire.decode(#"{"serverContent":{"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"AQI="}},{"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"AwQ="}}]},"inputTranscription":{"text":"こんにちは"},"outputTranscription":{"text":"Hello"},"turnComplete":true}}"#)
        #expect(message.audio == [Data([1, 2]), Data([3, 4])])
        #expect(message.input == "こんにちは")
        #expect(message.output == "Hello")
        #expect(message.turnComplete)
    }
    @Test(arguments: [#"{"error":{"message":"private-value"}}"#, #"{"goAway":{"timeLeft":"5s"}}"#, #"{"serverContent":{"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=16000","data":"AQI="}}]}}}"#, #"{"serverContent":{"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"AQ=="}}]}}}"#])
    func rejectsErrorsAndUnsupportedAudio(_ text: String) {
        #expect(throws: (any Error).self) { try GeminiWire.decode(text) }
    }
    @MainActor @Test(.timeLimit(.minutes(1))) func commonSessionReceivesTranscriptAndInterruptsPlayback() async throws {
        let socket = FakeSocket()
        let audio = FakeAudio()
        let session = GeminiConversationSession(configuration: .init(credential: .apiKey("test-key")), socket: socket, audio: audio)
        try await session.connect()
        #expect(session.state == .connected)
        #expect(audio.started)
        await session.setMicrophoneEnabled(false)
        #expect(!audio.enabled)
        socket.deliver(#"{"serverContent":{"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"AQI="}}]},"outputTranscription":{"text":"Hello"}}}"#)
        socket.deliver(#"{"serverContent":{"interrupted":true,"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"AwQ="}}]}}}"#)
        for try await event in session.events {
            if case .transcript(.assistant, "Hello", true) = event { break }
        }
        #expect(audio.played == [Data([1, 2])])
        #expect(audio.interrupts == 1)
        await session.close()
        #expect(session.state == .closed)
        #expect(audio.closed)
        #expect(socket.isClosed)
    }
    @MainActor @Test(.timeLimit(.minutes(1))) func closeDuringSetupDoesNotStartMicrophone() async throws {
        let socket = FakeSocket(autoSetup: false)
        let audio = FakeAudio()
        let session = GeminiConversationSession(configuration: .init(credential: .apiKey("test-key")), socket: socket, audio: audio)
        let call = Task { try await session.connect() }
        while !socket.hasSent { await Task.yield() }
        await session.close()
        do { try await call.value; Issue.record("Closed setup unexpectedly connected") } catch {}
        #expect(!audio.started)
        #expect(session.state == .closed)
    }
}

private final class FakeSocket: GeminiSocket, @unchecked Sendable {
    private let lock = NSLock()
    private let incoming: AsyncThrowingStream<String, any Error>
    private let continuation: AsyncThrowingStream<String, any Error>.Continuation
    private let autoSetup: Bool
    private var closed = false
    private var sent = false
    var isClosed: Bool { lock.lock(); defer { lock.unlock() }; return closed }
    var hasSent: Bool { lock.lock(); defer { lock.unlock() }; return sent }
    init(autoSetup: Bool = true) {
        self.autoSetup = autoSetup
        var sink: AsyncThrowingStream<String, any Error>.Continuation!
        incoming = AsyncThrowingStream { sink = $0 }
        continuation = sink
    }
    func open(_ url: URL) async throws {}
    func send(_ text: String) async throws { markSent(); if autoSetup { deliver(#"{"setupComplete":{}}"#) } }
    func receive() async throws -> String {
        var iterator = incoming.makeAsyncIterator()
        guard let value = try await iterator.next() else { throw ConversationError.closed }
        return value
    }
    func deliver(_ text: String) { continuation.yield(text) }
    func close() { lock.lock(); closed = true; lock.unlock(); continuation.finish(throwing: ConversationError.closed) }
    private func markSent() { lock.lock(); sent = true; lock.unlock() }
}
@MainActor private final class FakeAudio: GeminiAudio {
    var started = false
    var closed = false
    var enabled = true
    var interrupts = 0
    var played: [Data] = []
    private var continuation: AsyncThrowingStream<Data, any Error>.Continuation?
    func start() throws -> AsyncThrowingStream<Data, any Error> { started = true; return AsyncThrowingStream { continuation = $0 } }
    func play(_ bytes: Data) throws { played.append(bytes) }
    func interrupt() { interrupts += 1 }
    func setMicrophoneEnabled(_ enabled: Bool) { self.enabled = enabled }
    func close() { closed = true; continuation?.finish() }
}
