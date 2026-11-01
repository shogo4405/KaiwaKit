import Foundation
import Testing
@testable import KaiwaKit

@Suite struct RealtimeSessionTests {
    @Test func missingCredentialCanRetry() async throws {
        let session = RealtimeSession(
            uri: URL(string: "https://api.openai.com/v1/realtime/calls")!,
            mode: .publish,
            configuration: RealtimeSessionConfiguration(apiKey: " \n")
        )
        var states = await session.readyState.makeAsyncIterator()
        #expect(await states.next() == .closed)
        for _ in 0..<2 {
            await #expect(throws: RealtimeError.missingCredential) {
                try await session.connect {}
            }
            #expect(await states.next() == .connecting)
            #expect(await states.next() == .closing)
            #expect(await states.next() == .closed)
        }
    }

    @Test(arguments: [200, 201, 400, 401, 403, 429, 500])
    func httpStatusIsChecked(_ status: Int) throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/realtime/calls")!,
            statusCode: status, httpVersion: nil, headerFields: nil
        ))
        if status < 300 {
            try RealtimeHTTP.validate(response)
        } else {
            #expect(throws: RealtimeError.httpStatus(status)) {
                try RealtimeHTTP.validate(response)
            }
        }
    }

    @Test func audioTranscriptAndErrorEvents() throws {
        let decoder = JSONDecoder()
        let transcript = try decoder.decode(RealtimeEvent.self, from: Data(#"{"type":"response.output_audio_transcript.done","transcript":"Hello!"}"#.utf8))
        #expect(transcript.transcript == "Hello!")
        #expect(transcript.item == nil)
        let item = try decoder.decode(RealtimeEvent.self, from: Data(#"{"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_audio","transcript":"Hello!"}]}}"#.utf8))
        #expect(item.item?.content.first?.transcript == "Hello!")
        #expect(item.item?.content.first?.text == nil)
        let error = try decoder.decode(RealtimeEvent.self, from: Data(#"{"type":"error","error":{"message":"Invalid request"}}"#.utf8))
        #expect(error.error?.message == "Invalid request")
    }
}
