package com.haishinkit.kaiwakit.gemini

import com.haishinkit.rtc.RtcWebSocket

internal interface GeminiSocket {
    suspend fun open(url: String)

    fun send(text: String)

    suspend fun receive(): String

    fun close()
}

/** Uses libdatachannel through the HaishinKit native transport. No authenticated URLs are logged. */
internal class NativeGeminiSocket : GeminiSocket {
    private val socket = RtcWebSocket()

    override suspend fun open(url: String) = socket.connect(url)

    override fun send(text: String) = socket.send(text)

    override suspend fun receive(): String = socket.receive().text

    override fun close() = socket.close()
}
