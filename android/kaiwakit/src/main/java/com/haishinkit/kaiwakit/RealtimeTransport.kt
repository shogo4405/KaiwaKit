package com.haishinkit.kaiwakit

import android.content.Context
import com.haishinkit.rtc.RtcDuplexSession
import com.haishinkit.rtc.RtcStream

internal interface RealtimeTransport {
    val outgoing: RtcStream
    val incoming: RtcStream

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
    override val outgoing: RtcStream get() = session.outgoing
    override val incoming: RtcStream get() = session.incoming

    private val session = RtcDuplexSession(context)

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
