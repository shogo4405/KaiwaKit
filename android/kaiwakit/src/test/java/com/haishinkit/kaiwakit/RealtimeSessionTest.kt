package com.haishinkit.kaiwakit

import com.haishinkit.rtc.RtcStream
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean

class RealtimeSessionTest {
    @Test fun connectReturnsOnlyAfterTransportIsReadyAndCloseStopsIt() =
        runBlocking {
            val transport = FakeTransport()
            val session = RealtimeSession(RealtimeSessionConfiguration({ " fresh-secret " }), transport)
            try {
                withTimeout(3000) { session.connect() }
                assertEquals(RealtimeSession.State.CONNECTED, session.state.value)
                assertEquals("fresh-secret", transport.secret)
                session.close()
                assertTrue(transport.stopped.isCompleted)
                assertTrue(transport.disposed.get())
                assertEquals(RealtimeSession.State.CLOSED, session.state.value)
            } finally {
                session.close()
            }
        }

    @Test fun closeCancelsCredentialRequestAndCannotReopen() =
        runBlocking {
            val requested = CompletableDeferred<Unit>()
            val transport = FakeTransport()
            val session =
                RealtimeSession(
                    RealtimeSessionConfiguration({
                        requested.complete(Unit)
                        awaitCancellation()
                    }),
                    transport,
                )
            val connect = async { runCatching { session.connect() } }
            withTimeout(3000) { requested.await() }
            session.close()
            assertTrue(withTimeout(3000) { connect.await() }.isFailure)
            assertEquals(RealtimeSession.State.CLOSED, session.state.value)
            assertTrue(transport.disposed.get())
            assertTrue(runCatching { session.connect() }.isFailure)
        }

    @Test fun cancellingConnectStopsInFlightTransport() =
        runBlocking {
            val transport = FakeTransport(ready = false)
            val session = RealtimeSession(RealtimeSessionConfiguration({ "secret" }), transport)
            val connect = async { session.connect() }
            withTimeout(3000) { transport.started.await() }
            connect.cancelAndJoin()
            assertTrue(transport.stopped.isCompleted)
            assertEquals(RealtimeSession.State.CLOSED, session.state.value)
        }

    @Test fun transportFailureIsObservableAndDisposesResources() =
        runBlocking {
            val transport = FakeTransport(fail = true)
            val session = RealtimeSession(RealtimeSessionConfiguration({ "secret" }), transport)
            assertTrue(runCatching { withTimeout(3000) { session.connect() } }.isFailure)
            assertNotNull(session.failure.value)
            assertTrue(transport.disposed.get())
            assertEquals(RealtimeSession.State.CLOSED, session.state.value)
        }

    @Test fun credentialTimeoutReportsFailureAndReleasesResources() =
        runBlocking {
            val transport = FakeTransport()
            val session = RealtimeSession(RealtimeSessionConfiguration({ awaitCancellation() }, connectionTimeoutMillis = 50), transport)
            val failure = runCatching { withTimeout(3000) { session.connect() } }.exceptionOrNull()
            assertTrue(failure is IOException)
            assertNotNull(session.failure.value)
            assertTrue(transport.disposed.get())
            assertEquals(RealtimeSession.State.CLOSED, session.state.value)
        }

    @Test fun closeBeforeConnectReleasesResources() =
        runBlocking {
            val transport = FakeTransport()
            val session = RealtimeSession(RealtimeSessionConfiguration({ "secret" }), transport)
            session.close()
            session.close()
            assertTrue(transport.disposed.get())
            assertTrue(runCatching { session.connect() }.isFailure)
        }

    @Test fun unknownEventPayloadSurvivesDelivery() =
        runBlocking {
            val transport = FakeTransport()
            val session = RealtimeSession(RealtimeSessionConfiguration({ "secret" }), transport)
            val event = async(start = CoroutineStart.UNDISPATCHED) { session.events.first() }
            try {
                session.connect()
                transport.onText("""{"type":"future.event","custom":{"value":42}}""")
                val received = withTimeout(3000) { event.await() }
                assertEquals("future.event", received.type)
                assertTrue("custom" in received.payload)
            } finally {
                event.cancel()
                session.close()
            }
        }

    private class FakeTransport(private val ready: Boolean = true, private val fail: Boolean = false) : RealtimeTransport {
        override val outgoing: RtcStream get() = error("Not used in session tests")
        override val incoming: RtcStream get() = error("Not used in session tests")
        val started = CompletableDeferred<Unit>()
        val stopped = CompletableDeferred<Unit>()
        val disposed = AtomicBoolean()
        var secret = ""
        lateinit var onText: (String) -> Unit

        override suspend fun run(
            secret: String,
            onText: (String) -> Unit,
            onConnected: () -> Unit,
        ) {
            this.secret = secret
            this.onText = onText
            started.complete(Unit)
            try {
                if (fail) throw IOException("Test transport failure")
                if (ready) onConnected()
                awaitCancellation()
            } finally {
                stopped.complete(Unit)
            }
        }

        override fun send(text: String) {}

        override fun dispose() {
            disposed.set(true)
        }
    }
}
