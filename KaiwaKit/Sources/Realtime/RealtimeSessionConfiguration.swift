import HaishinKit
import RTCHaishinKit

/// Authentication and WebRTC transport settings for a ``RealtimeSession``.
///
/// Prefer ``clientSecret`` for distributed apps. ``apiKey`` is a convenience
/// for local development that allows the session to mint its own short-lived
/// Realtime token. Neither property represents a ChatGPT login session.
/// Credentials are held in memory and are included when this configuration is
/// encoded; do not log or persist its encoded representation.
///
/// Transport settings are passed through to HaishinKit/libdatachannel. Optional
/// settings left as `nil` use that implementation's defaults. Changing this value
/// after creating a session does not update the session's copied configuration.
public struct RealtimeSessionConfiguration: StreamSessionConfiguration, RTCConfigurationConvertible {
    /// A standard OpenAI API key used to request a short-lived Realtime token.
    ///
    /// Used only when ``clientSecret`` is absent or blank after trimming whitespace.
    /// For local development only; distributed apps should mint tokens on a backend.
    public var apiKey: String?
    /// A short-lived Realtime token issued by your authenticated backend.
    ///
    /// Supply the `value` returned by `/v1/realtime/client_secrets`. A nonempty
    /// trimmed value takes precedence over ``apiKey``. Configure audio output on
    /// the backend and obtain a fresh token before reconnecting after expiration.
    /// KaiwaKit does not refresh a supplied token automatically.
    public var clientSecret: String?

    // MARK: RTCConfigurationConvertible
    /// The STUN/TURN server URLs supplied to ICE. Defaults to an empty list.
    public var iceServers: [String] = []
    /// The local IP address to bind, or `nil` for automatic address selection.
    public var bindAddress: String?
    /// The DTLS certificate type, or `nil` for the library default.
    public var certificateType: RTCCertificateType?
    /// The ICE candidate selection policy, or `nil` for the library default.
    public var iceTransportPolicy: RTCTransportPolicy?
    /// Whether ICE UDP multiplexing is enabled. Defaults to `false`.
    public var isIceUdpMuxEnabled: Bool = false
    /// Whether automatic negotiation is enabled. Defaults to `true`.
    public var isAutoNegotionEnabled: Bool = true
    /// Whether to create media transport even without tracks. Defaults to `false`.
    public var isForceMediaTransport: Bool = false
    /// The port-range bounds supplied to ICE, or `nil` for automatic allocation.
    public var portRange: Range<UInt16>?
    /// The maximum transmission unit in bytes, or `nil` for automatic selection.
    public var mtu: Int32?
    /// The maximum data-channel message size in bytes, or `nil` for the library default.
    public var maxMesasgeSize: Int32?

    /// Creates authentication and transport settings without making a request.
    ///
    /// - Parameters:
    ///   - apiKey: A standard API key for local development. Defaults to `nil`.
    ///   - iceServers: STUN/TURN server URLs. Defaults to an empty list.
    ///   - bindAddress: A local IP address, or `nil` for automatic selection.
    ///   - certificateType: A DTLS certificate type, or `nil` for the library default.
    ///   - iceTransportPolicy: An ICE candidate policy, or `nil` for the library default.
    ///   - isIceUdpMuxEnabled: Whether ICE UDP multiplexing is enabled. Defaults to `false`.
    ///   - isAutoNegotionEnabled: Whether negotiation is automatic. Defaults to `true`.
    ///   - isForceMediaTransport: Whether to create media transport without tracks. Defaults to `false`.
    ///   - portRange: Port-range bounds supplied to ICE, or `nil` for automatic allocation.
    ///   - mtu: Maximum transmission unit in bytes, or `nil` for automatic selection.
    ///   - maxMesasgeSize: Maximum data-channel message size in bytes, or `nil` for the library default.
    ///   - clientSecret: A backend-issued Realtime token. A nonempty value takes
    ///     precedence over `apiKey`. Defaults to `nil`.
    public init(
        apiKey: String? = nil,
        iceServers: [String] = [],
        bindAddress: String? = nil,
        certificateType: RTCCertificateType? = nil,
        iceTransportPolicy: RTCTransportPolicy? = nil,
        isIceUdpMuxEnabled: Bool = false,
        isAutoNegotionEnabled: Bool = true,
        isForceMediaTransport: Bool = false,
        portRange: Range<UInt16>? = nil,
        mtu: Int32? = nil,
        maxMesasgeSize: Int32? = nil,
        clientSecret: String? = nil
    ) {
        self.apiKey = apiKey
        self.clientSecret = clientSecret
        self.iceServers = iceServers
        self.bindAddress = bindAddress
        self.certificateType = certificateType
        self.iceTransportPolicy = iceTransportPolicy
        self.isIceUdpMuxEnabled = isIceUdpMuxEnabled
        self.isAutoNegotionEnabled = isAutoNegotionEnabled
        self.isForceMediaTransport = isForceMediaTransport
        self.portRange = portRange
        self.mtu = mtu
        self.maxMesasgeSize = maxMesasgeSize
    }
}
