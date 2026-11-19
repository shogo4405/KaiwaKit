@preconcurrency import AVFoundation
import Foundation

@MainActor
protocol GeminiAudio: AnyObject {
    func start() throws -> AsyncThrowingStream<Data, any Error>
    func play(_ bytes: Data) throws
    func interrupt()
    func setMicrophoneEnabled(_ enabled: Bool)
    func close()
}

@MainActor
final class AppleGeminiAudio: GeminiAudio {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var capture: CaptureConverter?
    private var continuation: AsyncThrowingStream<Data, any Error>.Continuation?
    private var queuedFrames = 0
    private var generation = 0
    private var tapped = false
    private var enabled = true
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!

    func start() throws -> AsyncThrowingStream<Data, any Error> {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw ConversationError.audio }
        let converter = try CaptureConverter(format: format)
        converter.setEnabled(enabled)
        capture = converter
        var sink: AsyncThrowingStream<Data, any Error>.Continuation!
        let stream = AsyncThrowingStream<Data, any Error>(bufferingPolicy: .bufferingOldest(64)) { sink = $0 }
        continuation = sink
        let output = sink!
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            do {
                let bytes = try converter.convert(buffer)
                if !bytes.isEmpty, case .dropped = output.yield(bytes) { output.finish(throwing: ConversationError.overflow) }
            } catch { output.finish(throwing: ConversationError.audio) }
        }
        tapped = true
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        try engine.start()
        player.play()
        return stream
    }
    func play(_ bytes: Data) throws {
        guard bytes.count % 2 == 0 else { throw ConversationError.protocolMessage }
        let frames = bytes.count / 2
        guard frames > 0 else { return }
        guard queuedFrames + frames <= 120_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(frames)),
              let samples = buffer.floatChannelData?[0] else { throw ConversationError.overflow }
        buffer.frameLength = AVAudioFrameCount(frames)
        bytes.withUnsafeBytes { raw in
            let input = raw.bindMemory(to: UInt8.self)
            for index in 0..<frames {
                samples[index] = Float(Int16(bitPattern: UInt16(input[index * 2]) | UInt16(input[index * 2 + 1]) << 8)) / 32768
            }
        }
        queuedFrames += frames
        let current = generation
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.queuedFrames -= frames
            }
        }
    }
    func interrupt() {
        generation += 1
        queuedFrames = 0
        player.stop()
        if engine.isRunning { player.play() }
    }
    func setMicrophoneEnabled(_ enabled: Bool) { self.enabled = enabled; capture?.setEnabled(enabled) }
    func close() {
        continuation?.finish()
        continuation = nil
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        interrupt()
        engine.stop()
        player.stop()
        capture = nil
    }
}

private final class CaptureConverter: @unchecked Sendable {
    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private var enabled = true
    init(format: AVAudioFormat) throws {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: format, to: output) else { throw ConversationError.audio }
        outputFormat = output
        self.converter = converter
        converter.primeMethod = .none
    }
    func setEnabled(_ enabled: Bool) { lock.lock(); self.enabled = enabled; lock.unlock() }
    func convert(_ input: AVAudioPCMBuffer) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16_000 / input.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { throw ConversationError.audio }
        let source = ConverterInput(input)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            guard let input = source.take() else { status.pointee = .noDataNow; return nil }
            status.pointee = .haveData
            return input
        }
        guard error == nil, let data = output.int16ChannelData?[0] else { throw ConversationError.audio }
        let count = Int(output.frameLength) * 2
        return enabled ? Data(bytes: data, count: count) : Data(count: count)
    }
}

/// AVAudioConverter may invoke its Sendable input callback more than once.
/// Transfer the immutable input buffer once, with access protected across callbacks.
private final class ConverterInput: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        let result = buffer
        buffer = nil
        return result
    }
}
