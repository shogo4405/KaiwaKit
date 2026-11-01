import HaishinKit
import RTCHaishinKit
import Foundation

/// An OpenAI Realtime API session that sends and receives audio over WebRTC.
///
/// Use ``RealtimeSessionConfiguration`` to supply a short-lived client secret
/// from your backend, or an API key for local development. Connect a HaishinKit
/// `MediaMixer` to ``stream`` for microphone input and attach an `AudioPlayer`
/// to that stream before calling ``connect(_:)`` for audible responses.
///
/// Audio uses the WebRTC media track. ``events`` exposes a subset of the JSON
/// events received on the `oai-events` data channel, including audio transcripts.
/// The host application owns microphone permission, audio-session configuration,
/// capture start/stop, and the lifetime of its event-consumer tasks.
public actor RealtimeSession: StreamSession {
    static let endpoint = "https://api.openai.com/v1/realtime/calls"
    static let dataChannelLabel = "oai-events"

    /// Session state notifications, beginning with the current state.
    ///
    /// Each access creates a new sequence and finishes the previous sequence.
    /// Keep one consumer per session. The `.open` state means SDP negotiation
    /// has completed; inspect ``connected`` for the peer connection's state.
    /// Cancel your consumer when it is no longer needed; ``close()`` does not
    /// finish this sequence.
    public var readyState: AsyncStream<StreamSessionReadyState> {
        AsyncStream<StreamSessionReadyState> { contination in
            self.readyStateContination = contination
            contination.yield(_readyState)
        }
    }
    /// The HaishinKit stream used for outgoing capture and incoming playback.
    ///
    /// Add this stream to a `MediaMixer` and attach an `AudioPlayer` before
    /// connecting. Retain the player for the duration of the call. The session
    /// starts both media pipelines when its WebRTC peer becomes connected.
    public var stream: any StreamConvertible {
        _stream
    }
    /// Whether the underlying WebRTC peer is currently connected.
    ///
    /// This is a snapshot, not a sequence of notifications. It may still be
    /// `false` when ``connect(_:)`` returns after the SDP exchange.
    public var connected: Bool {
        get async {
            peerConnection?.connectionState == .connected
        }
    }
    /// Decodable Realtime events received as text messages on the data channel.
    ///
    /// Obtain this sequence before connecting to capture early events. Each
    /// access replaces and finishes the previous sequence, so use a single
    /// consumer. Payloads that cannot decode as ``RealtimeEvent`` and binary
    /// data-channel messages are ignored. Audio itself is played through ``stream``.
    /// Cancel the consumer at the end of a call; ``close()`` does not finish it.
    public var events: AsyncStream<RealtimeEvent> {
        AsyncStream<RealtimeEvent> { contination in
            self.eventsContination = contination
        }
    }
    private let uri: URL
    private var connectionID: UUID?
    private var disconnected: (@Sendable () -> Void)?
    private var maxRetryCount: Int = 5
    private var _stream = RTCStream()
    private let configuration: RealtimeSessionConfiguration?
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel? {
        didSet {
            dataChannel?.delegate = self
        }
    }
    private var _readyState: StreamSessionReadyState = .closed {
        didSet {
            readyStateContination?.yield(_readyState)
        }
    }
    private var readyStateContination: AsyncStream<StreamSessionReadyState>.Continuation? {
        didSet {
            oldValue?.finish()
        }
    }
    private var eventsContination: AsyncStream<RealtimeEvent>.Continuation? {
        didSet {
            oldValue?.finish()
        }
    }
    private lazy var jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    /// Creates a session without opening a network connection or capturing audio.
    ///
    /// The configuration is copied at initialization. Create a new session when
    /// a backend-issued client secret expires or you need different settings.
    ///
    /// - Parameters:
    ///   - uri: Accepted for `StreamSession` compatibility. This implementation
    ///     uses `https://api.openai.com/v1/realtime/calls` regardless of this value.
    ///   - mode: Accepted for `StreamSession` compatibility. Both modes use the
    ///     same bidirectional audio connection; `.publish` is the sample's convention.
    ///   - configuration: A ``RealtimeSessionConfiguration``. A `nil` value or a
    ///     different configuration type leaves the session without credentials,
    ///     causing ``connect(_:)`` to throw ``RealtimeError/missingCredential``.
    public init(uri: URL, mode: StreamSessionMode, configuration: (any StreamSessionConfiguration)?) {
        self.uri = URL(string: Self.endpoint) ?? uri
        self.configuration = configuration as? RealtimeSessionConfiguration
    }

    /// Stores a retry limit for `StreamSession` compatibility.
    ///
    /// Automatic retry is not implemented. Calling this method does not change
    /// connection behavior; the application must initiate a new connection.
    ///
    /// - Parameter maxRetryCount: The stored limit, currently unused.
    public func setMaxRetryCount(_ maxRetryCount: Int) {
        self.maxRetryCount = maxRetryCount
    }

    /// Exchanges an SDP offer with OpenAI and configures the WebRTC peer.
    ///
    /// A nonempty client secret takes precedence over the API key. When using
    /// an API key, the session first requests a short-lived secret configured
    /// for `gpt-realtime` with audio output. Backend-issued secrets retain the
    /// settings chosen by the backend.
    ///
    /// Returns after the SDP answer has been applied, before ICE/DTLS necessarily
    /// completes. Calls made while the session is not closed return without
    /// starting another connection. A failed attempt restores the closed state.
    ///
    /// - Parameter disconnected: Called after cleanup when the active peer
    ///   reports failure, disconnection, or closure. It is not called for an
    ///   explicit ``close()`` or an error thrown by this method. Dispatch UI work
    ///   to the main actor. No automatic reconnection is performed.
    /// - Throws: ``RealtimeError``, URL-loading or decoding errors, WebRTC setup
    ///   errors, or `CancellationError` if the attempt is cancelled or closed.
    public func connect(_ disconnected: @escaping @Sendable () -> Void) async throws {
        guard _readyState == .closed else {
            return
        }
        _readyState = .connecting
        let connectionID = UUID()
        self.connectionID = connectionID
        self.disconnected = disconnected
        do {
            let ephemeralKey: String
            if let clientSecret = RealtimeHTTP.credential(configuration?.clientSecret) {
                ephemeralKey = clientSecret
            } else {
                ephemeralKey = try await createClientSecret(configuration?.apiKey)
            }
            try Task.checkCancellation()
            guard self.connectionID == connectionID else { throw CancellationError() }
            let peerConnection = try makePeerConnection()
            self.peerConnection = peerConnection
            let audioSettings = await _stream.audioSettings
            guard self.connectionID == connectionID else { throw CancellationError() }
            try peerConnection.addTrack(AudioStreamTrack(audioSettings), stream: _stream)
            dataChannel = try peerConnection.createDataChannel(Self.dataChannelLabel)

            try peerConnection.setLocalDesciption(.offer)
            let answer = try await requestOffer(uri, offer: peerConnection.createOffer(), ephemeralKey: ephemeralKey)
            try Task.checkCancellation()
            guard self.connectionID == connectionID else { throw CancellationError() }
            try peerConnection.setRemoteDesciption(answer, type: .answer)
            _readyState = .open
        } catch {
            if self.connectionID == connectionID {
                try? await close()
            }
            throw error
        }
    }

    /// Closes the peer connection and stops both stream media pipelines.
    ///
    /// Safe to call while connecting, and a no-op when already closed or closing.
    /// A pending connection attempt cannot reopen the session after this call.
    /// The disconnection callback is not invoked for an explicit close.
    ///
    /// Stop and detach the application's `MediaMixer`, detach its `AudioPlayer`,
    /// and cancel event/state consumers separately. This method does not stop
    /// application-owned capture or finish ``events`` and ``readyState``.
    /// The throwing signature satisfies `StreamSession`; the current
    /// implementation does not throw during cleanup.
    public func close() async throws {
        guard _readyState != .closed, _readyState != .closing else { return }
        _readyState = .closing
        connectionID = nil
        disconnected = nil
        dataChannel?.delegate = nil
        dataChannel = nil
        peerConnection?.delegate = nil
        peerConnection?.close()
        peerConnection = nil
        await _stream.close()
        _readyState = .closed
    }

    private func createClientSecret(_ apiKey: String?) async throws -> String {
        guard let apiKey = RealtimeHTTP.credential(apiKey), let endpoint = URL(string: RealtimeClientSecrets.endpoint) else {
            throw RealtimeError.missingCredential
        }
        let clientSecrets = RealtimeClientSecrets.Request(
            expiresAfter: .init(anchor: "created_at", seconds: 600),
            session: .init(type: "realtime", model: "gpt-realtime")
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(clientSecrets)
        let (data, response) = try await URLSession.shared.data(for: request)
        try RealtimeHTTP.validate(response)
        let result = try JSONDecoder().decode(RealtimeClientSecrets.Response.self, from: data)
        guard let value = RealtimeHTTP.credential(result.value) else {
            throw RealtimeError.invalidResponse
        }
        return value
    }

    private func requestOffer(_ url: URL, offer: String, ephemeralKey: String) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(ephemeralKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = offer.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try RealtimeHTTP.validate(response)
        guard let answer = String(data: data, encoding: .utf8), answer.hasPrefix("v=0") else {
            throw RealtimeError.invalidResponse
        }
        return answer
    }

    private func connectionStateChanged(_ state: RTCPeerConnection.ConnectionState, id: ObjectIdentifier) async {
        guard let peerConnection, ObjectIdentifier(peerConnection) == id else { return }
        switch state {
        case .connected:
            await _stream.setDirection(.sendrecv)
        case .failed, .disconnected, .closed:
            let callback = disconnected
            try? await close()
            callback?()
        default:
            break
        }
    }

    private func makePeerConnection() throws -> RTCPeerConnection {
        let conneciton = try RTCPeerConnection(configuration)
        conneciton.delegate = self
        return conneciton
    }
}

extension RealtimeSession: RTCPeerConnectionDelegate {
    // MARK: RTCPeerConnectionDelegate
    /// Handles a peer-state callback by starting duplex media or cleaning up a lost connection.
    /// Called by HaishinKit; applications should use the session API instead.
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, connectionStateChanged connectionState: RTCPeerConnection.ConnectionState) {
        let id = ObjectIdentifier(peerConnection)
        Task {
            await connectionStateChanged(connectionState, id: id)
        }
    }

    /// Receives ICE gathering updates. This implementation performs no additional action.
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, iceGatheringStateChanged iceGatheringState: RTCPeerConnection.IceGatheringState) {
    }

    /// Receives ICE connection updates. Lifecycle handling uses the peer-state callback.
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, iceConnectionStateChanged iceConnectionState: RTCPeerConnection.IceConnectionState) {
    }

    /// Receives signaling updates. This implementation performs no additional action.
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, signalingStateChanged signalingState: RTCPeerConnection.SignalingState) {
    }

    /// Receives a remote data-channel callback; this session uses its locally created channel.
    nonisolated public func peerConnection(_ peerConneciton: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    }

    /// Receives an ICE candidate. This implementation does not send trickle-ICE updates.
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, gotIceCandidate candidated: RTCIceCandidate) {
    }
}

extension RealtimeSession: RTCDataChannelDelegate {
    // MARK: RTCDataChannelDelegate
    /// Receives data-channel state changes. This implementation performs no additional action.
    nonisolated public func dataChannel(_ dataChannel: RTCDataChannel, readyStateChanged readyState: RTCDataChannel.ReadyState) {
    }

    /// Decodes a text message and forwards supported payloads to ``events``.
    /// Messages that do not match ``RealtimeEvent`` are ignored.
    nonisolated public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessage message: String) {
        guard let event = try? JSONDecoder().decode(RealtimeEvent.self, from: Data(message.utf8)) else {
            return
        }
        Task {
            await eventsContination?.yield(event)
        }
    }

    /// Receives a binary data-channel message, which this implementation ignores.
    nonisolated public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessage message: Data) {
    }
}
