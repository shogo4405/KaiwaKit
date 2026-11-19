package com.haishinkit.kaiwakit.gemini

enum class GeminiCredentialKind { API_KEY, EPHEMERAL_TOKEN }

/** API keys are for local development; distributed apps should fetch a fresh token from a backend. */
class GeminiSessionConfiguration(
    val credentialProvider: suspend () -> String,
    val credentialKind: GeminiCredentialKind = GeminiCredentialKind.API_KEY,
    val model: String = DEFAULT_MODEL,
    val connectionTimeoutMillis: Long = 30_000,
) {
    init {
        require(model.isNotBlank())
        require(connectionTimeoutMillis > 0)
    }

    companion object {
        const val DEFAULT_MODEL = "gemini-3.8-live"
    }
}
