import AVFoundation
import Foundation
import Testing

@testable import KaiwaKit

@Suite struct RealtimeClientSecretsTests {
    @Test func clientSecretsRequest() throws {
        let request = RealtimeClientSecrets.Request(expiresAfter: .init(anchor: "created_at", seconds: 360), session: .init(type: "foo", model: "bar"))
        let data = try! JSONEncoder().encode(request)
    }

    @Test func clientSecretsResponse() throws {
        let json = """
        {
          "value": "ek_68af296e8e408191a1120ab6383263c2",
          "expires_at": 1756310470,
          "session": {
            "type": "realtime",
            "object": "realtime.session",
            "id": "sess_C9CiUVUzUzYIssh3ELY1d",
            "model": "gpt-realtime",
            "output_modalities": [
              "audio"
            ],
            "instructions": "You are a friendly assistant.",
            "tools": [],
            "tool_choice": "auto",
            "max_output_tokens": "inf",
            "tracing": null,
            "truncation": "auto",
            "prompt": null,
            "expires_at": 0,
            "audio": {
              "input": {
                "format": {
                  "type": "audio/pcm",
                  "rate": 24000
                },
                "transcription": null,
                "noise_reduction": null,
                "turn_detection": {
                  "type": "server_vad",
                }
              },
              "output": {
                "format": {
                  "type": "audio/pcm",
                  "rate": 24000
                },
                "voice": "alloy",
                "speed": 1.0
              }
            },
            "include": null
          }
        }
        """

        let jsonData = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(RealtimeClientSecrets.Response.self, from: jsonData)

        #expect(response.value == "ek_68af296e8e408191a1120ab6383263c2")
    }
}
