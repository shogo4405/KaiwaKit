import HaishinKit
import RTCHaishinKit

public struct RealtimeSessionConfiguration: StreamSessionConfiguration, RTCConfigurationConvertible {
    /// For local development only. Distributed apps should use a client secret.
    public var apiKey: String?
    /// A short-lived Realtime token issued by your backend. Takes precedence over apiKey.
    public var clientSecret: String?

    // MARK: RTCConfigurationConvertible
    public var iceServers: [String] = []
    public var bindAddress: String?
    public var certificateType: RTCCertificateType?
    public var iceTransportPolicy: RTCTransportPolicy?
    public var isIceUdpMuxEnabled: Bool = false
    public var isAutoNegotionEnabled: Bool = true
    public var isForceMediaTransport: Bool = false
    public var portRange: Range<UInt16>?
    public var mtu: Int32?
    public var maxMesasgeSize: Int32?

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
