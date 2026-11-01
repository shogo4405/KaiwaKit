# ``KaiwaKit``

Connect to the OpenAI Realtime API over WebRTC using HaishinKit.

## Overview

``RealtimeSession`` exchanges SDP with OpenAI, sends microphone audio through
HaishinKit, and receives the model's audio on the same WebRTC connection. Attach
an `AudioPlayer` to the session's stream for playback. Transcripts and server
errors are available through ``RealtimeSession/events``.

Supply a backend-issued token with ``RealtimeSessionConfiguration/clientSecret``.
For local development, ``RealtimeSessionConfiguration/apiKey`` lets the session
request a short-lived token itself. The configuration's encoded form contains
its credentials and must not be logged.

The application manages microphone permission, `AVAudioSession` on iOS,
`MediaMixer` capture, and the lifetime of its player and asynchronous consumers.
Stop capture and cancel consumers when ending a call, in addition to calling
``RealtimeSession/close()``. The session does not automatically reconnect.

The iOS/macOS sample in `Examples/Shared` shows the complete lifecycle. See the
[OpenAI WebRTC guide](https://developers.openai.com/api/docs/guides/voice-webrtc)
for the server-side token issuance flow.

## Topics

### Session lifecycle

- ``RealtimeSession``
- ``RealtimeSessionConfiguration``

### Events and errors

- ``RealtimeEvent``
- ``RealtimeError``
