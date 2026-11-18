package com.haishinkit.kaiwakit

import android.content.Context
import com.haishinkit.rtc.RTCDuplexSession
import com.haishinkit.rtc.RTCStream

internal interface RealtimeTransport {
    val outgoing: RTCStream
    val incoming: RTCStream

    suspend fun run(
        secret: String,
        onText: (String) -> Unit,
        onConnected: () -> Unit,
    )

    fun send(text: String)

    fun dispose()
}

internal class HaishinKitTransport(
    context: Context,
    private val configuration: RealtimeSessionConfiguration,
) : RealtimeTransport {
    override val outgoing: RTCStream get() = session.outgoing
    override val incoming: RTCStream get() = session.incoming

    private val session = RTCDuplexSession(context)

    override suspend fun run(
        secret: String,
        onText: (String) -> Unit,
        onConnected: () -> Unit,
    ) {
        session.run(
            dataChannelLabel = "oai-events",
            iceServers = configuration.iceServers,
            timeoutMillis = configuration.connectionTimeoutMillis,
            exchange = { RealtimeHTTP.exchange(it, secret) },
            onText = onText,
            onConnected = onConnected,
        )
    }

    override fun send(text: String) = session.send(text)

    override fun dispose() = session.dispose()
}
