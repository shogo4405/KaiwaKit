package com.haishinkit.kaiwakit

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

internal object RealtimeHTTP {
    private const val ENDPOINT = "https://api.openai.com/v1/realtime/calls"
    private const val MAX_RESPONSE_BYTES = 1024 * 1024

    suspend fun exchange(
        offer: String,
        secret: String,
        connection: HttpURLConnection = URL(ENDPOINT).openConnection() as HttpURLConnection,
    ): String = post(offer.toByteArray(Charsets.UTF_8), secret, "application/sdp", "Realtime SDP request", connection)

    internal suspend fun post(
        body: ByteArray,
        credential: String,
        contentType: String,
        operation: String,
        connection: HttpURLConnection,
    ): String =
        coroutineScope {
            require(credential.isNotBlank()) { "Credential is empty" }
            suspendCancellableCoroutine { continuation ->
                continuation.invokeOnCancellation { connection.disconnect() }
                launch(Dispatchers.IO) {
                    try {
                        connection.requestMethod = "POST"
                        connection.instanceFollowRedirects = false
                        connection.connectTimeout = 15_000
                        connection.readTimeout = 15_000
                        connection.setRequestProperty("Authorization", "Bearer $credential")
                        connection.setRequestProperty("Content-Type", contentType)
                        connection.doOutput = true
                        connection.outputStream.use { it.write(body) }
                        val status = connection.responseCode
                        // Do not expose response bodies, which may contain credentials or personal data.
                        if (status !in 200..299) throw RealtimeRequestException(status, operation)
                        val bytes =
                            connection.inputStream.use { input ->
                                val output = ByteArrayOutputStream()
                                val buffer = ByteArray(8192)
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    if (output.size() + count > MAX_RESPONSE_BYTES) throw IOException("OpenAI response is too large")
                                    output.write(buffer, 0, count)
                                }
                                output.toByteArray()
                            }
                        val answer = bytes.toString(Charsets.UTF_8)
                        if (continuation.isActive) continuation.resume(answer)
                    } catch (cause: Exception) {
                        if (continuation.isActive) continuation.resumeWithException(cause)
                    } finally {
                        connection.disconnect()
                    }
                }
            }
        }
}
