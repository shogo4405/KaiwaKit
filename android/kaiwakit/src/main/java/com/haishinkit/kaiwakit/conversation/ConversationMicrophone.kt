package com.haishinkit.kaiwakit.conversation

import android.content.Context
import android.media.AudioRecord
import android.media.MediaRecorder
import com.haishinkit.media.MediaBuffer
import com.haishinkit.media.MediaMixer
import com.haishinkit.media.MediaType
import com.haishinkit.media.source.AudioRecordSource
import com.haishinkit.media.source.AudioSource
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Serializes the mixer's asynchronous open/close requests with foreground call cleanup. */
internal class ConversationMicrophone(context: Context) : AudioSource {
    @Volatile override var isMuted = false

    private val recorder =
        AudioRecordSource(context).apply {
            sampleRate = 48_000
            audioSource = MediaRecorder.AudioSource.VOICE_COMMUNICATION
        }
    private val mutex = Mutex()

    @Volatile private var closed = false
    private var opened = false
    private var device: AudioRecord? = null

    override suspend fun open(mixer: MediaMixer): Result<Unit> =
        mutex.withLock {
            when {
                closed -> Result.failure(IllegalStateException("Microphone is closed"))
                opened -> Result.success(Unit)
                else -> {
                    device = checkNotNull(recorder.audioRecord) { "Microphone permission is required" }
                    recorder.open(mixer).also { opened = it.isSuccess }
                }
            }
        }

    override suspend fun close(): Result<Unit> =
        mutex.withLock {
            if (closed) return@withLock Result.success(Unit)
            closed = true
            runCatching {
                device?.let { audio ->
                    try {
                        if (audio.recordingState == AudioRecord.RECORDSTATE_RECORDING) audio.stop()
                    } finally {
                        audio.release()
                    }
                }
                device = null
            }
        }

    override fun read(track: Int): MediaBuffer =
        if (closed) {
            MediaBuffer(type = MediaType.AUDIO, index = track, payload = null, timestamp = 0, sync = true)
        } else {
            recorder.isMuted = isMuted
            recorder.read(track)
        }
}
