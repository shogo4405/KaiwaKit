package com.haishinkit.kaiwakit.sample

import android.content.Context
import android.media.AudioManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.haishinkit.kaiwakit.RealtimeSession
import com.haishinkit.kaiwakit.RealtimeSessionConfiguration
import com.haishinkit.media.MediaMixer
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Foreground-only sample. Credentials and transcripts are kept in memory. */
internal class ConversationController(private val context: Context) {
    var status by mutableStateOf("Ready")
        private set
    var active by mutableStateOf(false)
        private set
    var transcript by mutableStateOf("")
        private set
    var muted by mutableStateOf(false)
        private set

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var call: Job? = null
    private var source: CallMicrophone? = null

    fun start(clientSecret: String) {
        if (call != null || clientSecret.isBlank()) return
        active = true
        muted = false
        transcript = ""
        status = "Connecting…"
        call =
            scope.launch(start = CoroutineStart.LAZY) {
                val audioManager = context.getSystemService(AudioManager::class.java)
                val oldMode = audioManager.mode
                var mixer: MediaMixer? = null
                var session: RealtimeSession? = null
                try {
                    audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                    val capture = MediaMixer(context)
                    mixer = capture
                    val realtime = RealtimeSession(context, RealtimeSessionConfiguration({ clientSecret }))
                    session = realtime
                    val microphone = CallMicrophone(context).apply { isMuted = muted }
                    source = microphone
                    capture.registerOutput(realtime.outgoing)
                    coroutineScope {
                        launch {
                            realtime.events.collect { event ->
                                when (event.type) {
                                    "response.output_audio_transcript.done" -> event.transcript?.let { append("Assistant: $it") }
                                    "conversation.item.input_audio_transcription.completed" -> event.transcript?.let { append("You: $it") }
                                    "error" -> status = "The server reported an error. Stop and try a new token."
                                }
                            }
                        }
                        launch { throw realtime.failure.filterNotNull().first() }
                        realtime.connect()
                        withContext(Dispatchers.IO) { capture.attachAudio(0, microphone).getOrThrow() }
                        capture.startRunning()
                        status = "Connected"
                        awaitCancellation()
                    }
                } catch (_: CancellationException) {
                    status = "Stopped"
                } catch (_: Exception) {
                    status = "Connection failed. Check your network and use a fresh client secret."
                } finally {
                    withContext(NonCancellable) {
                        mixer?.stopRunning()
                        session?.close()
                        session?.let { mixer?.unregisterOutput(it.outgoing) }
                        withContext(Dispatchers.IO) { source?.close() }
                        mixer?.dispose()
                        audioManager.mode = oldMode
                    }
                    source = null
                    muted = false
                    active = false
                    call = null
                }
            }
        call?.start()
    }

    fun toggleMute() {
        muted = !muted
        source?.isMuted = muted
    }

    fun stop() {
        call?.cancel()
    }

    fun dispose() {
        scope.cancel()
    }

    private fun append(text: String) {
        // Keep long calls from growing the sample UI without bound.
        transcript = (transcript + text + "\n\n").takeLast(32_000)
    }
}
