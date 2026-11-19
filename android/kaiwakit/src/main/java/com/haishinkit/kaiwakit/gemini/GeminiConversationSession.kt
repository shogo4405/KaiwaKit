package com.haishinkit.kaiwakit.gemini

import android.content.Context
import com.haishinkit.kaiwakit.conversation.ConversationEvent
import com.haishinkit.kaiwakit.conversation.ConversationRunner
import com.haishinkit.kaiwakit.conversation.ConversationSession
import com.haishinkit.kaiwakit.conversation.Speaker
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import java.io.IOException

/** Gemini Live over WebSocket. The host owns microphone permission and communication audio routing. */
class GeminiConversationSession internal constructor(
    private val configuration: GeminiSessionConfiguration,
    private val audio: GeminiAudio,
    private val socket: GeminiSocket,
) : ConversationSession {
    override val state get() = runner.state
    override val failure get() = runner.failure
    override val events get() = runner.events
    private val runner: ConversationRunner = ConversationRunner { ready -> execute(ready) }
    private var inputText = ""
    private var outputText = ""

    constructor(context: Context, configuration: GeminiSessionConfiguration) :
        this(configuration, AndroidGeminiAudio(context.applicationContext), NativeGeminiSocket())

    override suspend fun connect() = runner.connect()

    override suspend fun close() = runner.close()

    override fun setMicrophoneEnabled(enabled: Boolean) = audio.setMicrophoneEnabled(enabled)

    private suspend fun execute(ready: () -> Unit): Unit =
        coroutineScope {
            try {
                val first =
                    withTimeout(configuration.connectionTimeoutMillis) {
                        val credential = configuration.credentialProvider().trim()
                        socket.open(GeminiWire.url(credential, configuration.credentialKind))
                        socket.send(GeminiWire.setup(configuration.model))
                        var message = GeminiWire.decode(socket.receive())
                        while (!message.setupComplete) {
                            message = GeminiWire.decode(socket.receive())
                        }
                        message
                    }
                val capture = audio.start(this)
                launch { for (bytes in capture) socket.send(GeminiWire.audio(bytes)) }
                handle(first)
                ready()
                while (true) handle(GeminiWire.decode(socket.receive()))
            } finally {
                try {
                    audio.close()
                } finally {
                    socket.close()
                }
            }
        }

    private fun handle(message: GeminiWire.Message) {
        if (message.interrupted) {
            audio.interrupt()
            runner.emit(ConversationEvent.Interrupted)
        } else {
            message.audio.forEach(audio::play)
        }
        message.input?.let {
            if (inputText.length + it.length > 65536) throw IOException("Gemini transcript is too large")
            inputText += it
            runner.emit(ConversationEvent.Transcript(Speaker.USER, inputText, false))
        }
        message.output?.let {
            if (outputText.length + it.length > 65536) throw IOException("Gemini transcript is too large")
            outputText += it
            runner.emit(ConversationEvent.Transcript(Speaker.ASSISTANT, outputText, false))
        }
        if (message.inputFinished || message.turnComplete || message.interrupted) {
            if (inputText.isNotEmpty()) runner.emit(ConversationEvent.Transcript(Speaker.USER, inputText, true))
            inputText = ""
        }
        if (message.outputFinished || message.turnComplete || message.interrupted) {
            if (outputText.isNotEmpty()) runner.emit(ConversationEvent.Transcript(Speaker.ASSISTANT, outputText, true))
            outputText = ""
        }
    }
}
