package com.haishinkit.kaiwakit

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class RealtimeHTTPTest {
    @Test fun postsSdpWithBearerAndDisablesRedirects() =
        runBlocking {
            val connection = FakeConnection(201, "v=0\r\n")
            val answer = RealtimeHTTP.exchange("offer", "short-lived-token", connection)
            assertEquals("v=0\r\n", answer)
            assertEquals("POST", connection.requestMethod)
            assertEquals("Bearer short-lived-token", connection.getRequestProperty("Authorization"))
            assertEquals("application/sdp", connection.getRequestProperty("Content-Type"))
            assertEquals("offer", connection.output.toString("UTF-8"))
            assertFalse(connection.instanceFollowRedirects)
            assertTrue(connection.disconnected.get())
        }

    @Test fun errorsAndRedirectsDoNotExposeResponseBody() =
        runBlocking {
            for (status in listOf(302, 401, 429, 500)) {
                val connection = FakeConnection(status, "sensitive-response-body")
                val failure = runCatching { RealtimeHTTP.exchange("offer", "token", connection) }.exceptionOrNull()
                assertTrue(failure is IOException)
                assertEquals("Realtime SDP request failed (HTTP $status)", failure?.message)
                assertFalse(connection.inputOpened.get())
                assertTrue(connection.disconnected.get())
            }
        }

    @Test fun boundsResponseSize() =
        runBlocking {
            val connection = FakeConnection(200, "x".repeat(1024 * 1024 + 1))
            assertTrue(runCatching { RealtimeHTTP.exchange("offer", "token", connection) }.exceptionOrNull() is IOException)
            assertTrue(connection.disconnected.get())
        }

    @Test fun cancellationDisconnectsBlockedHttpRead() =
        runBlocking {
            val reading = CompletableDeferred<Unit>()
            val released = CountDownLatch(1)
            val connection =
                object : FakeConnection(200, "") {
                    override fun getInputStream(): InputStream =
                        object : InputStream() {
                            override fun read(): Int {
                                reading.complete(Unit)
                                check(released.await(3, TimeUnit.SECONDS)) { "Cancellation did not disconnect HTTP" }
                                throw IOException("Disconnected")
                            }
                        }

                    override fun disconnect() {
                        super.disconnect()
                        released.countDown()
                    }
                }
            val request = async { RealtimeHTTP.exchange("offer", "token", connection) }
            withTimeout(3000) { reading.await() }
            withTimeout(3000) { request.cancelAndJoin() }
            assertTrue(connection.disconnected.get())
        }

    private open class FakeConnection(private val status: Int, private val body: String) : HttpURLConnection(
        URL("https://example.invalid"),
    ) {
        val output = ByteArrayOutputStream()
        val disconnected = AtomicBoolean()
        val inputOpened = AtomicBoolean()

        override fun connect() {}

        override fun disconnect() {
            disconnected.set(true)
        }

        override fun usingProxy() = false

        override fun getOutputStream() = output

        override fun getResponseCode() = status

        override fun getInputStream(): InputStream {
            inputOpened.set(true)
            return ByteArrayInputStream(body.toByteArray())
        }
    }
}
