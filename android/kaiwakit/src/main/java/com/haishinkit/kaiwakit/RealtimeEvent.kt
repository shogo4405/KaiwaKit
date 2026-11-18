package com.haishinkit.kaiwakit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/** Unknown event types and fields are preserved in [payload]. */
data class RealtimeEvent(val type: String, val payload: JsonObject) {
    val transcript: String?
        get() = payload["transcript"]?.let { runCatching { it.jsonPrimitive.contentOrNull }.getOrNull() }
    val delta: String?
        get() = payload["delta"]?.let { runCatching { it.jsonPrimitive.contentOrNull }.getOrNull() }

    companion object {
        fun parse(text: String): RealtimeEvent {
            val payload =
                Json.parseToJsonElement(text) as? JsonObject
                    ?: throw IllegalArgumentException("Expected a Realtime JSON object")
            val type = payload["type"]?.jsonPrimitive?.contentOrNull
            require(!type.isNullOrBlank()) { "Realtime event is missing its type" }
            return RealtimeEvent(type, payload)
        }
    }
}
