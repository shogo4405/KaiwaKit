package com.haishinkit.kaiwakit.gemini

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import java.io.IOException
import java.util.Base64

internal object GeminiWire {
    fun url(
        credential: String,
        kind: GeminiCredentialKind,
    ): String {
        require(credential.isNotBlank()) { "Gemini credential is empty" }
        val method = if (kind == GeminiCredentialKind.API_KEY) "BidiGenerateContent" else "BidiGenerateContentConstrained"
        val encoded = java.net.URLEncoder.encode(credential.trim(), "UTF-8").replace("+", "%20")
        val parameter = if (kind == GeminiCredentialKind.API_KEY) "key" else "access_token"
        val path = "google.ai.generativelanguage.v1beta.GenerativeService.$method"
        return "wss://generativelanguage.googleapis.com/ws/$path?$parameter=$encoded"
    }

    fun setup(model: String): String =
        buildJsonObject {
            putJsonObject("setup") {
                put("model", if (model.startsWith("models/")) model else "models/$model")
                putJsonObject("generationConfig") { putJsonArray("responseModalities") { add(JsonPrimitive("AUDIO")) } }
                putJsonObject(
                    "systemInstruction",
                ) { putJsonArray("parts") { add(buildJsonObject { put("text", "You are a friendly assistant.") }) } }
                putJsonObject("inputAudioTranscription") {}
                putJsonObject("outputAudioTranscription") {}
            }
        }.toString()

    fun audio(bytes: ByteArray): String =
        buildJsonObject {
            putJsonObject("realtimeInput") {
                putJsonObject("audio") {
                    put("mimeType", "audio/pcm;rate=16000")
                    put("data", Base64.getEncoder().encodeToString(bytes))
                }
            }
        }.toString()

    fun decode(text: String): Message {
        if (text.length > 1024 * 1024) throw IOException("Gemini message is too large")
        try {
            val root = Json.parseToJsonElement(text).jsonObject
            if (root["error"] != null) throw IOException("Gemini reported an API error; check model and credential")
            if (root["goAway"] != null) throw IOException("Gemini session is expiring; reconnect with a fresh credential")
            val content = root["serverContent"]?.jsonObject
            val audio =
                content?.get("modelTurn")?.jsonObject?.get("parts")?.jsonArray.orEmpty().mapNotNull { part ->
                    val inline = part.jsonObject["inlineData"]?.jsonObject ?: return@mapNotNull null
                    val mime = inline["mimeType"]?.jsonPrimitive?.content.orEmpty()
                    if (mime.substringBefore(";").trim() != "audio/pcm") return@mapNotNull null
                    if (mime.split(";").drop(1).map {
                            it.trim()
                        }.any { it.startsWith("rate=") && it != "rate=24000" }
                    ) {
                        throw IOException("Unsupported Gemini audio sample rate")
                    }
                    Base64.getDecoder().decode(inline.getValue("data").jsonPrimitive.content).also {
                        if (it.size % 2 != 0) throw IOException("Invalid Gemini PCM audio")
                    }
                }
            val input = content?.get("inputTranscription")?.jsonObject
            val output = content?.get("outputTranscription")?.jsonObject
            return Message(
                setupComplete = root["setupComplete"] is JsonObject,
                audio = audio,
                input = input?.get("text")?.jsonPrimitive?.content,
                output = output?.get("text")?.jsonPrimitive?.content,
                inputFinished = input?.get("finished")?.jsonPrimitive?.content == "true",
                outputFinished = output?.get("finished")?.jsonPrimitive?.content == "true",
                turnComplete = content?.get("turnComplete")?.jsonPrimitive?.content == "true",
                interrupted = content?.get("interrupted")?.jsonPrimitive?.content == "true",
            )
        } catch (cause: IOException) {
            throw cause
        } catch (_: Exception) {
            throw IOException("Invalid Gemini server message")
        }
    }

    data class Message(
        val setupComplete: Boolean = false,
        val audio: List<ByteArray> = emptyList(),
        val input: String? = null,
        val output: String? = null,
        val inputFinished: Boolean = false,
        val outputFinished: Boolean = false,
        val turnComplete: Boolean = false,
        val interrupted: Boolean = false,
    )
}
