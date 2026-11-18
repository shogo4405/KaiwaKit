package com.haishinkit.kaiwakit

/** Obtain a fresh, short-lived client secret from your authenticated backend per call. */
class RealtimeSessionConfiguration(
    val clientSecretProvider: suspend () -> String,
    val iceServers: List<String> = emptyList(),
    val connectionTimeoutMillis: Long = 30_000,
) {
    init {
        require(connectionTimeoutMillis > 0)
    }
}
