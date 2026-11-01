import HaishinKit
import RTCHaishinKit
import Foundation

public actor RealtimeSession: StreamSession {
    static let endpoint = "https://api.openai.com/v1/realtime/calls"
    static let dataChannelLabel = "oai-events"

    public var readyState: AsyncStream<StreamSessionReadyState> {
        AsyncStream<StreamSessionReadyState> { contination in
            self.readyStateContination = contination
            contination.yield(_readyState)
        }
    }
    public var stream: any StreamConvertible {
        _stream
    }
    public var connected: Bool {
        get async {
            peerConnection?.connectionState == .connected
        }
    }
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

    public init(uri: URL, mode: StreamSessionMode, configuration: (any StreamSessionConfiguration)?) {
        self.uri = URL(string: Self.endpoint) ?? uri
        self.configuration = configuration as? RealtimeSessionConfiguration
    }

    public func setMaxRetryCount(_ maxRetryCount: Int) {
        self.maxRetryCount = maxRetryCount
    }

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
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, connectionStateChanged connectionState: RTCPeerConnection.ConnectionState) {
        let id = ObjectIdentifier(peerConnection)
        Task {
            await connectionStateChanged(connectionState, id: id)
        }
    }

    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, iceGatheringStateChanged iceGatheringState: RTCPeerConnection.IceGatheringState) {
    }

    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, iceConnectionStateChanged iceConnectionState: RTCPeerConnection.IceConnectionState) {
    }

    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, signalingStateChanged signalingState: RTCPeerConnection.SignalingState) {
    }

    nonisolated public func peerConnection(_ peerConneciton: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    }

    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, gotIceCandidate candidated: RTCIceCandidate) {
    }
}

extension RealtimeSession: RTCDataChannelDelegate {
    // MARK: RTCDataChannelDelegate
    nonisolated public func dataChannel(_ dataChannel: RTCDataChannel, readyStateChanged readyState: RTCDataChannel.ReadyState) {
    }

    nonisolated public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessage message: String) {
        guard let event = try? JSONDecoder().decode(RealtimeEvent.self, from: Data(message.utf8)) else {
            return
        }
        Task {
            await eventsContination?.yield(event)
        }
    }

    nonisolated public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessage message: Data) {
    }
}
