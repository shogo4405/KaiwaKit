package com.haishinkit.kaiwakit.sample

import android.content.Context
import android.media.AudioManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.haishinkit.kaiwakit.RealtimeClientSecrets
import com.haishinkit.kaiwakit.RealtimeRequestException
import com.haishinkit.kaiwakit.RealtimeSessionConfiguration
import com.haishinkit.kaiwakit.conversation.ConversationEvent
import com.haishinkit.kaiwakit.conversation.ConversationProvider
import com.haishinkit.kaiwakit.conversation.ConversationSession
import com.haishinkit.kaiwakit.conversation.OpenAIConversationSession
import com.haishinkit.kaiwakit.conversation.Speaker
import com.haishinkit.kaiwakit.gemini.GeminiConversationSession
import com.haishinkit.kaiwakit.gemini.GeminiCredentialKind
import com.haishinkit.kaiwakit.gemini.GeminiSessionConfiguration
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

/** Foreground-only sample. Switching services never reuses the previous service's credential. */
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
    private var session: ConversationSession? = null

    fun start(
        credential: String,
        credentialKind: CredentialKind,
        provider: ConversationProvider,
        model: String,
    ) {
        if (call != null || credential.isBlank()) return
        active = true
        muted = false
        transcript = ""
        status = "Connecting to ${provider.displayName}…"
        call =
            scope.launch(start = CoroutineStart.LAZY) {
                val manager = context.getSystemService(AudioManager::class.java)
                val oldMode = manager.mode
                var current: ConversationSession? = null
                try {
                    manager.mode = AudioManager.MODE_IN_COMMUNICATION
                    val conversation: ConversationSession =
                        when (provider) {
                            ConversationProvider.OPENAI ->
                                OpenAIConversationSession(
                                    context,
                                    RealtimeSessionConfiguration({
                                        if (credentialKind == CredentialKind.API_KEY) {
                                            RealtimeClientSecrets.create(credential)
                                        } else {
                                            credential
                                        }
                                    }),
                                )
                            ConversationProvider.GEMINI ->
                                GeminiConversationSession(
                                    context,
                                    GeminiSessionConfiguration(
                                        credentialProvider = { credential },
                                        credentialKind =
                                            if (credentialKind == CredentialKind.API_KEY) {
                                                GeminiCredentialKind.API_KEY
                                            } else {
                                                GeminiCredentialKind.EPHEMERAL_TOKEN
                                            },
                                        model = model.trim(),
                                    ),
                                )
                        }
                    current = conversation
                    session = conversation
                    coroutineScope {
                        launch {
                            conversation.events.collect { event ->
                                if (event is ConversationEvent.Transcript && event.isFinal) {
                                    val role = if (event.speaker == Speaker.USER) "You" else provider.displayName
                                    transcript = (transcript + "$role: ${event.text}\n\n").takeLast(32_000)
                                }
                            }
                        }
                        launch { throw conversation.failure.filterNotNull().first() }
                        conversation.connect()
                        status = "Connected to ${provider.displayName}"
                        awaitCancellation()
                    }
                } catch (_: CancellationException) {
                    status = "Stopped"
                } catch (cause: RealtimeRequestException) {
                    status =
                        when (cause.statusCode) {
                            401 -> "OpenAI rejected this credential. Check it and try again."
                            403 -> "This API account does not have access to Realtime."
                            429 -> "OpenAI quota or rate limit reached. Check API billing or try again later."
                            else -> "OpenAI request failed (HTTP ${cause.statusCode})."
                        }
                } catch (_: Exception) {
                    status = "${provider.displayName} connection failed. Check network, credential and model access."
                } finally {
                    withContext(NonCancellable) {
                        try {
                            current?.close()
                        } finally {
                            manager.mode = oldMode
                        }
                    }
                    session = null
                    muted = false
                    active = false
                    call = null
                }
            }
        call?.start()
    }

    fun toggleMute() {
        muted = !muted
        session?.setMicrophoneEnabled(!muted)
    }

    fun stop() {
        call?.cancel()
    }

    fun dispose() {
        scope.cancel()
    }
}
