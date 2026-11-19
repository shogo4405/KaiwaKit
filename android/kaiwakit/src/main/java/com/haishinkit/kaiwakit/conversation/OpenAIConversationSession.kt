package com.haishinkit.kaiwakit.conversation

import android.content.Context
import com.haishinkit.kaiwakit.RealtimeSession
import com.haishinkit.kaiwakit.RealtimeSessionConfiguration
import com.haishinkit.media.MediaMixer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException

/** OpenAI WebRTC adapter with independently owned microphone capture and remote playback. */
class OpenAIConversationSession(
    context: Context,
    private val configuration: RealtimeSessionConfiguration,
) : ConversationSession {
    override val state get() = runner.state
    override val failure get() = runner.failure
    override val events get() = runner.events
    private val applicationContext = context.applicationContext
    private val runner: ConversationRunner = ConversationRunner { ready -> execute(ready) }

    @Volatile private var microphone: ConversationMicrophone? = null

    @Volatile private var microphoneEnabled = true

    override suspend fun connect() = runner.connect()

    override suspend fun close() = runner.close()

    override fun setMicrophoneEnabled(enabled: Boolean) {
        microphoneEnabled = enabled
        microphone?.isMuted = !enabled
    }

    private suspend fun execute(ready: () -> Unit): Unit =
        coroutineScope {
            val session = RealtimeSession(applicationContext, configuration)
            val mixer = MediaMixer(applicationContext)
            val source = ConversationMicrophone(applicationContext).apply { isMuted = !microphoneEnabled }
            microphone = source
            try {
                mixer.registerOutput(session.outgoing)
                launch { throw session.failure.filterNotNull().first() }
                launch {
                    session.events.collect { event ->
                        when (event.type) {
                            "response.output_audio_transcript.done" ->
                                event.transcript?.let {
                                    runner.emit(ConversationEvent.Transcript(Speaker.ASSISTANT, it, true))
                                }
                            "conversation.item.input_audio_transcription.completed" ->
                                event.transcript?.let {
                                    runner.emit(ConversationEvent.Transcript(Speaker.USER, it, true))
                                }
                            "input_audio_buffer.speech_started" -> runner.emit(ConversationEvent.Interrupted)
                            "error" -> throw IOException("OpenAI reported a Realtime API error")
                        }
                    }
                }
                session.connect()
                withContext(Dispatchers.IO) { mixer.attachAudio(0, source).getOrThrow() }
                mixer.startRunning()
                ready()
                awaitCancellation()
            } finally {
                withContext(NonCancellable) {
                    mixer.stopRunning()
                    try {
                        session.close()
                    } finally {
                        mixer.unregisterOutput(session.outgoing)
                        withContext(Dispatchers.IO) { source.close() }
                        mixer.dispose()
                        microphone = null
                    }
                }
            }
        }
}
