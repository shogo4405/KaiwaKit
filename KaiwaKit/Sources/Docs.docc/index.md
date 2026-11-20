# ``KaiwaKit``

Build native voice conversations with OpenAI Realtime and Gemini Live.

## Overview

Use ``ConversationSession`` for a common connection lifecycle, microphone mute,
transcripts, and interruption events. ``OpenAIConversationSession`` connects over
WebRTC and ``GeminiConversationSession`` connects over WebSocket. Both own their
microphone capture and response playback. The host application grants microphone
permission and configures its audio route. Subscribe to events before connecting,
create a new session for each call, and close it when the call ends.

For OpenAI, supply a backend-issued client secret with
``RealtimeSessionConfiguration/clientSecret``. For Gemini, supply a backend-issued
``GeminiCredential/ephemeralToken(_:)``. API keys are also supported for local
development; keep production keys on your backend. Credentials must not be logged.

### Lower-level OpenAI sessions

``RealtimeSession`` exchanges SDP with OpenAI, sends microphone audio through
HaishinKit, and receives the model's audio on the same WebRTC connection. Attach
an `AudioPlayer` to the session's stream for playback. Transcripts and server
errors are available through ``RealtimeSession/events``.

With this lower-level API, the application manages `MediaMixer` capture and the
lifetime of its player and asynchronous consumers. Stop capture and cancel
consumers when ending a call, in addition to calling ``RealtimeSession/close()``.
Sessions do not automatically reconnect.

## Topics

### Integration guide

- <doc:GettingStarted>

### Common conversation API

- ``ConversationSession``
- ``ConversationProvider``
- ``ConversationState``
- ``ConversationEvent``
- ``ConversationSpeaker``

### OpenAI Realtime

- ``OpenAIConversationSession``
- ``RealtimeSession``
- ``RealtimeSessionConfiguration``
- ``RealtimeEvent``
- ``RealtimeError``

### Gemini Live

- ``GeminiConversationSession``
- ``GeminiSessionConfiguration``
- ``GeminiCredential``
