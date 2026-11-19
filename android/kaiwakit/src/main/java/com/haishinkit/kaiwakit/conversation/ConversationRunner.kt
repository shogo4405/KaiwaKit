package com.haishinkit.kaiwakit.conversation

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
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException

internal class ConversationRunner(private val execute: suspend (() -> Unit) -> Unit) {
    val state get() = mutableState.asStateFlow()
    val failure get() = mutableFailure.asStateFlow()
    val events get() = mutableEvents.asSharedFlow()
    private val mutableState = MutableStateFlow(ConversationState.IDLE)
    private val mutableFailure = MutableStateFlow<Throwable?>(null)
    private val mutableEvents = MutableSharedFlow<ConversationEvent>(extraBufferCapacity = 64)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val guard = Any()
    private var job: Job? = null
    private var closed = false

    fun emit(event: ConversationEvent) {
        if (!mutableEvents.tryEmit(event)) throw IOException("Conversation event consumer is too slow")
    }

    suspend fun connect() {
        val started = CompletableDeferred<Unit>()
        val run =
            synchronized(guard) {
                check(!closed && job == null) { "Create a new conversation for each call" }
                mutableState.value = ConversationState.CONNECTING
                scope.launch(start = CoroutineStart.LAZY) {
                    try {
                        execute {
                            synchronized(guard) {
                                if (closed) throw CancellationException("Conversation closed")
                                mutableState.value = ConversationState.CONNECTED
                            }
                            started.complete(Unit)
                        }
                    } catch (cause: Throwable) {
                        val reported =
                            if (cause is TimeoutCancellationException) {
                                IOException(
                                    "Conversation connection timed out",
                                )
                            } else {
                                cause
                            }
                        if (reported !is CancellationException) mutableFailure.value = reported
                        started.completeExceptionally(reported)
                    } finally {
                        mutableState.value = ConversationState.CLOSED
                        scope.cancel()
                    }
                }.also {
                    job = it
                    it.invokeOnCompletion { started.completeExceptionally(CancellationException("Conversation closed")) }
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

    suspend fun close() {
        val active =
            synchronized(guard) {
                closed = true
                if (mutableState.value != ConversationState.CLOSED) mutableState.value = ConversationState.CLOSING
                job
            }
        withContext(NonCancellable) { active?.cancelAndJoin() }
        scope.cancel()
        mutableState.value = ConversationState.CLOSED
    }
}
