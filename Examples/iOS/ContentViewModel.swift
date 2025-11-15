import AVFoundation
import HaishinKit
import Photos
import RTCHaishinKit
import SwiftUI
import KaiwaKit

@MainActor
final class ContentViewModel: ObservableObject {
    @Published private(set) var readyState: SessionReadyState = .closed
    @Published var lines: String = ""

    private(set) var mixer = MediaMixer(captureSessionMode: .single)
    private var session = RealtimeSession(uri: URL(string: "https://api.openai.com/v1/realtime")!, mode: .publish, configuration: RealtimeSessionConfiguration(
                                            apiKey: "")
    )

    init() {
        Task {
            for await event in await session.events where event.type == "response.output_item.done" {
                for content in event.item.content {
                    lines = "💬 \(content.text)\r\n" + lines
                }
            }
        }
    }

    func startRunning() {
        Task {
            let audiosession = AVAudioSession.sharedInstance()
            do {
                try audiosession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                try audiosession.setActive(true)
            } catch {
                print(error)
            }
            try? await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
            await mixer.addOutput(session.stream)
            await mixer.startRunning()
        }
        Task {
            for await readyState in await session.readyState {
                self.readyState = readyState
                switch readyState {
                case .open:
                    UIApplication.shared.isIdleTimerDisabled = false
                default:
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            }
        }
    }

    func stopRunning() {
        Task {
            await mixer.stopRunning()
            try? await mixer.attachAudio(nil)
        }
    }

    func connect() {
        Task {
            do {
                try await session.connect {
                }
            } catch {
                print(error)
            }
        }
    }

    func close() {
        Task {
            try await session.close()
        }
    }
}
