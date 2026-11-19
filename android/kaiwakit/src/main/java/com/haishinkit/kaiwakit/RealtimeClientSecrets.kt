package com.haishinkit.kaiwakit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** Client-secret issuance for local development. Distributed apps should issue secrets on a backend. */
object RealtimeClientSecrets {
    private const val ENDPOINT = "https://api.openai.com/v1/realtime/client_secrets"

    /**
     * Exchanges a manually entered API key for a short-lived `gpt-realtime` audio credential.
     * Nothing is stored. Call for each connection; cancellation disconnects the HTTP request.
     */
    suspend fun create(apiKey: String): String = create(apiKey, URL(ENDPOINT).openConnection() as HttpURLConnection)

    internal suspend fun create(
        apiKey: String,
        connection: HttpURLConnection,
    ): String {
        val key = apiKey.trim()
        require(key.isNotEmpty()) { "API key is empty" }
        val request =
            buildJsonObject {
                putJsonObject("expires_after") {
                    put("anchor", "created_at")
                    put("seconds", 600)
                }
                putJsonObject("session") {
                    put("type", "realtime")
                    put("model", "gpt-realtime")
                    put("instructions", "You are a friendly assistant.")
                    put("output_modalities", JsonArray(listOf(JsonPrimitive("audio"))))
                }
            }
        val response =
            RealtimeHTTP.post(
                request.toString().toByteArray(Charsets.UTF_8),
                key,
                "application/json",
                "Realtime client secret request",
                connection,
            )
        return decode(response)
    }

    private fun decode(response: String): String {
        val payload =
            try {
                Json.parseToJsonElement(response) as? JsonObject
            } catch (_: IllegalArgumentException) {
                null
            }
        val value = payload?.get("value") as? JsonPrimitive
        if (value?.isString != true || value.content.isBlank()) {
            throw IOException("OpenAI returned an invalid Realtime client secret")
        }
        return value.content.trim()
    }
}
