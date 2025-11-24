import HaishinKit
import RTCHaishinKit
import Foundation

public actor RealtimeSession: Session {
    static let endpoint = "https://api.openai.com/v1/realtime/calls"
    static let dataChannelLabel = "oai-events"

    enum Error: Swift.Error {
        case notFoundClientSecrets
    }

    public var readyState: AsyncStream<SessionReadyState> {
        AsyncStream<SessionReadyState> { contination in
            self.readyStateContination = contination
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
    private var location: URL?
    private var maxRetryCount: Int = 5
    private var _stream = RTCStream()
    private let configuration: RealtimeSessionConfiguration?
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel? {
        didSet {
            dataChannel?.delegate = self
        }
    }
    private var _readyState: SessionReadyState = .closed {
        didSet {
            readyStateContination?.yield(_readyState)
        }
    }
    private var readyStateContination: AsyncStream<SessionReadyState>.Continuation? {
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

    public init(uri: URL, mode: SessionMode, configuration: (any SessionConfiguration)?) {
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
        let ephemeralKey = try await createClientSecret(configuration?.apiKey)
        let peerConnection = try makePeerConnection()
        do {
            let audioSettings = await _stream.audioSettings
            try peerConnection.addTrack(AudioStreamTrack(audioSettings), stream: _stream)
            dataChannel = try? peerConnection.createDataChannel(Self.dataChannelLabel)

            try peerConnection.setLocalDesciption(.offer)
            let answer = try await requestOffer(uri, offer: peerConnection.createOffer(), ephemeralKey: ephemeralKey)
            try peerConnection.setRemoteDesciption(answer, type: .answer)
            self.peerConnection = peerConnection
            _readyState = .open
        } catch {
            await _stream.close()
            peerConnection.close()
            _readyState = .closed
            throw error
        }
    }

    public func close() async throws {
        guard _readyState == .open else {
            return
        }
        _readyState = .closing
        await _stream.close()
        peerConnection?.close()
        _readyState = .closed
    }

    private func createClientSecret(_ apiKey: String?) async throws -> String {
        guard let apiKey, let endpoint = URL(string: RealtimeClientSecrets.endpoint) else {
            throw Error.notFoundClientSecrets
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
        let (data, _) = try await URLSession.shared.data(for: request)
        let result = try JSONDecoder().decode(RealtimeClientSecrets.Response.self, from: data)
        return result.value
    }

    private func requestOffer(_ url: URL, offer: String, ephemeralKey: String) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(ephemeralKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = offer.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let response = response as? HTTPURLResponse {
            if let location = response.allHeaderFields["Location"] as? String {
                if location.hasSuffix("http") {
                    self.location = URL(string: location)
                } else {
                    var baseURL = "\(url.scheme ?? "http")://\(url.host ?? "")"
                    if let port = url.port {
                        baseURL += ":\(port)"
                    }
                    self.location = URL(string: "\(baseURL)\(location)")
                }
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
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
        Task {
            if connectionState == .connected {
                await _stream.setDirection(.sendonly)
            }
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
        guard let event = try? JSONDecoder().decode(RealtimeEvent.self, from: message.data(using: .utf8)!) else {
            return
        }
        Task {
            await eventsContination?.yield(event)
        }
    }

    nonisolated public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessage message: Data) {
    }
}
