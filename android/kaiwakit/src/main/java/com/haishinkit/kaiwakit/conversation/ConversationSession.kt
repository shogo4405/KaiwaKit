package com.haishinkit.kaiwakit.conversation

import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow

/** Transport-independent voice call. Grant microphone permission and configure audio routing first. */
interface ConversationSession {
    val state: StateFlow<ConversationState>
    val failure: StateFlow<Throwable?>
    val events: SharedFlow<ConversationEvent>

    /** Returns when transport and audio are ready. Create one instance per call. */
    suspend fun connect()

    /** Cancels setup or an active call and waits for audio and transport cleanup. */
    suspend fun close()

    fun setMicrophoneEnabled(enabled: Boolean)
}

enum class ConversationState { IDLE, CONNECTING, CONNECTED, CLOSING, CLOSED }

enum class ConversationProvider(val displayName: String) { OPENAI("OpenAI"), GEMINI("Gemini") }

enum class Speaker { USER, ASSISTANT }

sealed interface ConversationEvent {
    /** [text] is cumulative for the current segment; [isFinal] ends that segment. */
    data class Transcript(val speaker: Speaker, val text: String, val isFinal: Boolean) : ConversationEvent

    data object Interrupted : ConversationEvent
}
