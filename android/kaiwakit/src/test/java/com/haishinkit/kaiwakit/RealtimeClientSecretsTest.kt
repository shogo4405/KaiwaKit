package com.haishinkit.kaiwakit

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

class RealtimeClientSecretsTest {
    @Test fun issuesAudioSecretWithTrimmedApiKeyAndExpectedSession() =
        runBlocking {
            val connection = FakeConnection(200, """{"value":"ephemeral-test-secret","expires_at":12345,"session":{"type":"realtime"}}""")
            assertEquals("ephemeral-test-secret", RealtimeClientSecrets.create("  development-test-key  ", connection))
            assertEquals("POST", connection.requestMethod)
            assertEquals("Bearer development-test-key", connection.getRequestProperty("Authorization"))
            assertEquals("application/json", connection.getRequestProperty("Content-Type"))
            assertFalse(connection.instanceFollowRedirects)
            val request = Json.parseToJsonElement(connection.output.toString("UTF-8")).jsonObject
            val session = request.getValue("session").jsonObject
            assertEquals("realtime", session.getValue("type").jsonPrimitive.content)
            assertEquals("gpt-realtime", session.getValue("model").jsonPrimitive.content)
            assertEquals(listOf("audio"), session.getValue("output_modalities").jsonArray.map { it.jsonPrimitive.content })
            val expires = request.getValue("expires_after").jsonObject
            assertEquals("created_at", expires.getValue("anchor").jsonPrimitive.content)
            assertEquals("600", expires.getValue("seconds").jsonPrimitive.content)
            assertFalse(connection.output.toString("UTF-8").contains("development-test-key"))
            assertTrue(connection.disconnected)
        }

    @Test fun rejectsEmptyApiKeyBeforeOpeningHttpRequest() =
        runBlocking {
            val connection = FakeConnection(200, "{}")
            assertTrue(runCatching { RealtimeClientSecrets.create(" \n ", connection) }.exceptionOrNull() is IllegalArgumentException)
            assertFalse(connection.requested)
        }

    @Test fun rejectsMalformedAndMissingSecretsWithoutExposingResponse() =
        runBlocking {
            val invalid =
                listOf(
                    "not-json-sensitive-value",
                    "[]",
                    "{}",
                    """{"value":" "}""",
                    """{"value":123}""",
                    """{"value":null}""",
                    """{"value":{}}""",
                )
            for (body in invalid) {
                val connection = FakeConnection(200, body)
                val error = runCatching { RealtimeClientSecrets.create("test-key", connection) }.exceptionOrNull()
                assertTrue(error is IOException)
                assertEquals("OpenAI returned an invalid Realtime client secret", error?.message)
                assertTrue(connection.disconnected)
            }
        }

    @Test fun exposesHttpStatusWithoutCredentialOrServerBody() =
        runBlocking {
            for (status in listOf(302, 401, 403, 429, 500)) {
                val connection = FakeConnection(status, "private-server-response")
                val error = runCatching { RealtimeClientSecrets.create("private-test-key", connection) }.exceptionOrNull()
                assertTrue(error is RealtimeRequestException)
                assertEquals(status, (error as RealtimeRequestException).statusCode)
                assertEquals("Realtime client secret request failed (HTTP $status)", error.message)
                assertFalse(connection.inputOpened)
                assertTrue(connection.disconnected)
            }
        }

    @Test fun acceptsUnknownResponseFieldsAndTrimsSecret() =
        runBlocking {
            val connection = FakeConnection(200, """{"value":"  ephemeral-secret  ","future":{"field":true}}""")
            assertEquals("ephemeral-secret", RealtimeClientSecrets.create("test-key", connection))
        }

    private class FakeConnection(private val status: Int, private val body: String) : HttpURLConnection(URL("https://example.invalid")) {
        val output = ByteArrayOutputStream()
        var requested = false
        var disconnected = false
        var inputOpened = false

        override fun connect() {}

        override fun disconnect() {
            disconnected = true
        }

        override fun usingProxy() = false

        override fun getOutputStream(): ByteArrayOutputStream {
            requested = true
            return output
        }

        override fun getResponseCode() = status

        override fun getInputStream(): ByteArrayInputStream {
            inputOpened = true
            return ByteArrayInputStream(body.toByteArray())
        }
    }
}
