import HaishinKit
import RTCHaishinKit

public struct RealtimeSessionConfiguration: SessionConfiguration, RTCConfigurationConvertible {
    public var apiKey: String?

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
        maxMesasgeSize: Int32? = nil
    ) {
        self.apiKey = apiKey
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
