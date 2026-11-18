package com.haishinkit.kaiwakit

import android.content.Context
import com.haishinkit.rtc.RTCStream
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.JsonObject
import java.io.IOException

/**
 * A single OpenAI Realtime voice call. Create a new instance (and fetch a new secret) per call.
 * The host owns microphone permission, audio routing and the capture mixer. Register [outgoing]
 * with the mixer. Incoming audio plays through [incoming] without a view. Stop/detach capture
 * separately when closing. Start collecting [events] before connecting; events are not replayed.
 */
class RealtimeSession internal constructor(
    private val configuration: RealtimeSessionConfiguration,
    private val transport: RealtimeTransport,
) {
    val state: StateFlow<State> get() = mutableState.asStateFlow()
    val failure: StateFlow<Throwable?> get() = mutableFailure.asStateFlow()
    val events: SharedFlow<RealtimeEvent> get() = mutableEvents.asSharedFlow()
    val outgoing: RTCStream get() = transport.outgoing
    val incoming: RTCStream get() = transport.incoming

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val guard = Any()
    private val mutableState = MutableStateFlow(State.IDLE)
    private val mutableFailure = MutableStateFlow<Throwable?>(null)
    private val mutableEvents = MutableSharedFlow<RealtimeEvent>(extraBufferCapacity = 64)
    private var job: Job? = null
    private var closed = false

    constructor(context: Context, configuration: RealtimeSessionConfiguration) :
        this(configuration, HaishinKitTransport(context.applicationContext, configuration))

    /** Returns when audio and data transport are ready. Cancellation closes the attempt. */
    suspend fun connect() {
        val started = CompletableDeferred<Unit>()
        val run =
            synchronized(guard) {
                check(!closed && job == null) { "Create a new session for each call" }
                mutableState.value = State.CONNECTING
                scope.launch(start = CoroutineStart.LAZY) {
                    try {
                        val secret =
                            withTimeout(configuration.connectionTimeoutMillis) {
                                configuration.clientSecretProvider().trim().also { require(it.isNotEmpty()) { "Client secret is empty" } }
                            }
                        transport.run(
                            secret,
                            onText = { text ->
                                val event = RealtimeEvent.parse(text)
                                if (!mutableEvents.tryEmit(event)) throw IOException("Realtime event consumer is too slow")
                            },
                            onConnected = {
                                synchronized(guard) {
                                    if (closed) throw CancellationException("Session closed")
                                    mutableState.value = State.CONNECTED
                                }
                                started.complete(Unit)
                            },
                        )
                    } catch (cause: Throwable) {
                        val reported =
                            if (cause is TimeoutCancellationException) {
                                IOException(
                                    "Realtime connection timed out",
                                    cause,
                                )
                            } else {
                                cause
                            }
                        if (reported !is CancellationException) mutableFailure.value = reported
                        started.completeExceptionally(reported)
                    } finally {
                        transport.dispose()
                        mutableState.value = State.CLOSED
                        scope.cancel()
                    }
                }.also { created ->
                    job = created
                    created.invokeOnCompletion { started.completeExceptionally(CancellationException("Session closed")) }
                }
            }
        run.start()
        try {
            started.await()
        } catch (cause: Throwable) {
            withContext(NonCancellable) { close() }
            throw cause
        }
    }

    /** JSON client events use the data channel; microphone audio uses its media track. */
    fun send(event: JsonObject) {
        check(mutableState.value == State.CONNECTED) { "Session is not connected" }
        transport.send(event.toString())
    }

    /** Cancels an in-flight connection and waits for media and native resources to stop. */
    suspend fun close() {
        val active =
            synchronized(guard) {
                closed = true
                if (mutableState.value != State.CLOSED) mutableState.value = State.CLOSING
                job
            }
        withContext(NonCancellable) { active?.cancelAndJoin() }
        scope.cancel()
        transport.dispose()
        mutableState.value = State.CLOSED
    }

    enum class State { IDLE, CONNECTING, CONNECTED, CLOSING, CLOSED }
}
