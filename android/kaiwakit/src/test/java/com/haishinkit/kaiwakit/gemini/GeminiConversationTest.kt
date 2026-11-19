package com.haishinkit.kaiwakit.gemini

import com.haishinkit.kaiwakit.conversation.ConversationEvent
import com.haishinkit.kaiwakit.conversation.ConversationState
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.util.concurrent.ConcurrentLinkedQueue

class GeminiConversationTest {
    @Test fun endpointEscapesCredentialsAndSelectsConstrainedTokenApi() {
        val key = GeminiWire.url("a+&?/", GeminiCredentialKind.API_KEY)
        val token = GeminiWire.url("test", GeminiCredentialKind.EPHEMERAL_TOKEN)
        assertTrue(key.contains("?key=a%2B%26%3F%2F"))
        assertTrue(token.contains("BidiGenerateContentConstrained?access_token="))
        val setup = Json.parseToJsonElement(GeminiWire.setup("test-model")).jsonObject.getValue("setup").jsonObject
        assertNotNull(setup["inputAudioTranscription"])
        assertNotNull(setup["outputAudioTranscription"])
        assertTrue(GeminiWire.audio(byteArrayOf(1, 2)).contains("AQI="))
    }

    @Test fun parserProcessesAllAudioAndTranscriptParts() {
        val message =
            GeminiWire.decode(
                """
                {"serverContent":{"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000",
                "data":"AQI="}},
                {"inlineData":{"mimeType":"audio/pcm;rate=24000",
                "data":"AwQ="}}]},
                "outputTranscription":{"text":"こんにちは"},
                "turnComplete":true}}
                """.trimIndent(),
            )
        assertEquals(2, message.audio.size)
        assertArrayEquals(byteArrayOf(1, 2), message.audio[0])
        assertEquals("こんにちは", message.output)
        assertTrue(message.turnComplete)
        assertThrows(IOException::class.java) { GeminiWire.decode("""{"error":{"message":"sensitive-value"}}""") }
        assertThrows(IOException::class.java) {
            GeminiWire.decode(
                """{"serverContent":{"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"AQ=="}}]}}}""",
            )
        }
    }

    @Test fun sessionUsesCommonEventsAndClearsInterruptedAudio() =
        runBlocking {
            val socket = FakeSocket()
            val audio = FakeAudio()
            val session = GeminiConversationSession(GeminiSessionConfiguration({ "test" }), audio, socket)
            val transcript =
                async(start = CoroutineStart.UNDISPATCHED) {
                    session.events.filterIsInstance<ConversationEvent.Transcript>().first { it.isFinal }
                }
            try {
                withTimeout(3000) { session.connect() }
                assertEquals(ConversationState.CONNECTED, session.state.value)
                session.setMicrophoneEnabled(false)
                assertFalse(audio.enabled)
                socket.incoming.send(
                    """
                    {"serverContent":{"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000",
                    "data":"AQI="}}]},
                    "outputTranscription":{"text":"Hello"}}}
                    """.trimIndent(),
                )
                socket.incoming.send(
                    """
                    {"serverContent":{"interrupted":true,
                    "modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000",
                    "data":"AwQ="}}]}}}
                    """.trimIndent(),
                )
                assertEquals("Hello", withTimeout(3000) { transcript.await() }.text)
                assertEquals(1, audio.played.size)
                assertEquals(1, audio.interrupts)
            } finally {
                transcript.cancel()
                session.close()
            }
            assertTrue(audio.closed)
            assertTrue(socket.closed)
        }

    @Test fun closeWhileConnectingCannotReopenOrStartCapture() =
        runBlocking {
            val socket = FakeSocket(false)
            val audio = FakeAudio()
            val session = GeminiConversationSession(GeminiSessionConfiguration({ "test" }), audio, socket)
            val connect = async { runCatching { session.connect() } }
            withTimeout(3000) { socket.opened.await() }
            session.close()
            assertTrue(withTimeout(3000) { connect.await() }.isFailure)
            assertFalse(audio.started)
            assertEquals(ConversationState.CLOSED, session.state.value)
        }

    private class FakeSocket(private val autoSetup: Boolean = true) : GeminiSocket {
        val incoming = Channel<String>(16)
        val opened = CompletableDeferred<Unit>()

        @Volatile var closed = false

        override suspend fun open(url: String) {
            opened.complete(Unit)
        }

        override fun send(text: String) {
            if (autoSetup && "setup" in text) incoming.trySend("""{"setupComplete":{}}""")
        }

        override suspend fun receive() = incoming.receive()

        override fun close() {
            closed = true
            incoming.cancel()
        }
    }

    private class FakeAudio : GeminiAudio {
        val played = ConcurrentLinkedQueue<ByteArray>()

        @Volatile var started = false

        @Volatile var closed = false

        @Volatile var enabled = true

        @Volatile var interrupts = 0
        private val capture = Channel<ByteArray>(8)

        override fun start(scope: CoroutineScope): ReceiveChannel<ByteArray> {
            started = true
            return capture
        }

        override fun play(bytes: ByteArray) {
            played.add(bytes)
        }

        override fun interrupt() {
            interrupts++
        }

        override fun setMicrophoneEnabled(enabled: Boolean) {
            this.enabled = enabled
        }

        override fun close() {
            closed = true
            capture.cancel()
        }
    }
}
