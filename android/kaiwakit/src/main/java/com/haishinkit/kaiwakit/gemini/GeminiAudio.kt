package com.haishinkit.kaiwakit.gemini

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.IOException

internal interface GeminiAudio {
    fun start(scope: CoroutineScope): ReceiveChannel<ByteArray>

    fun play(bytes: ByteArray)

    fun interrupt()

    fun setMicrophoneEnabled(enabled: Boolean)

    fun close()
}

/** PCM capture is 16 kHz mono; playback is 24 kHz mono. No received audio enters capture. */
internal class AndroidGeminiAudio(private val context: Context) : GeminiAudio {
    private val capture = Channel<ByteArray>(64)
    private val playback = Channel<Chunk>(64)
    private val outputGuard = Any()
    private var recorder: AudioRecord? = null
    private var track: AudioTrack? = null
    private var generation = 0
    private var pendingBytes = 0

    @Volatile private var enabled = true

    @Volatile private var closed = false

    @SuppressLint("MissingPermission")
    override fun start(scope: CoroutineScope): ReceiveChannel<ByteArray> {
        check(!closed && recorder == null)
        check(context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            "Microphone permission is required"
        }
        val minimumInput = AudioRecord.getMinBufferSize(16_000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val minimumOutput = AudioTrack.getMinBufferSize(24_000, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        recorder =
            AudioRecord.Builder().setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
                .setAudioFormat(
                    AudioFormat.Builder().setSampleRate(16_000).setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO).build(),
                )
                .setBufferSizeInBytes(maxOf(6400, minimumInput)).build()
        track =
            AudioTrack.Builder().setAudioAttributes(
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build(),
            )
                .setAudioFormat(
                    AudioFormat.Builder().setSampleRate(24_000).setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build(),
                )
                .setBufferSizeInBytes(maxOf(9600, minimumOutput))
                .setTransferMode(AudioTrack.MODE_STREAM).build()
        val input = checkNotNull(recorder)
        check(
            input.state == AudioRecord.STATE_INITIALIZED && track?.state == AudioTrack.STATE_INITIALIZED,
        ) { "PCM audio initialization failed" }
        input.startRecording()
        track?.play()
        scope.launch(Dispatchers.IO) {
            val bytes = ByteArray(640)
            while (isActive && !closed) {
                val count = input.read(bytes, 0, bytes.size, AudioRecord.READ_BLOCKING)
                currentCoroutineContext().ensureActive()
                if (closed) break
                if (count < 0) throw IOException("Microphone capture failed")
                if (count == 0) {
                    delay(2)
                    continue
                }
                capture.send(if (enabled) bytes.copyOf(count) else ByteArray(count))
            }
        }
        scope.launch(Dispatchers.IO) {
            for (chunk in playback) {
                var offset = 0
                while (offset < chunk.bytes.size && isActive && !closed) {
                    val written =
                        synchronized(outputGuard) {
                            if (chunk.generation != generation) {
                                -1
                            } else {
                                track?.write(chunk.bytes, offset, chunk.bytes.size - offset, AudioTrack.WRITE_NON_BLOCKING) ?: -1
                            }
                        }
                    if (written < 0) {
                        if (chunk.generation != synchronized(outputGuard) { generation } || closed) break
                        throw IOException("Audio playback failed")
                    }
                    offset += written
                    if (written == 0) delay(2)
                }
                synchronized(outputGuard) { if (chunk.generation == generation) pendingBytes -= chunk.bytes.size }
            }
        }
        return capture
    }

    override fun play(bytes: ByteArray) {
        if (bytes.isEmpty()) return
        synchronized(outputGuard) {
            if (closed) return
            if (bytes.size % 2 != 0 || pendingBytes + bytes.size > 240_000) throw IOException("Gemini playback queue capacity exceeded")
            if (playback.trySend(Chunk(bytes, generation)).isFailure) throw IOException("Gemini playback queue capacity exceeded")
            pendingBytes += bytes.size
        }
    }

    override fun interrupt() {
        synchronized(outputGuard) {
            generation++
            pendingBytes = 0
            while (playback.tryReceive().isSuccess) { /* Drop audio from the interrupted turn. */ }
            track?.pause()
            track?.flush()
            if (!closed) track?.play()
        }
    }

    override fun setMicrophoneEnabled(enabled: Boolean) {
        this.enabled = enabled
    }

    override fun close() {
        closed = true
        capture.cancel()
        playback.cancel()
        try {
            recorder?.let { input ->
                try {
                    if (input.recordingState == AudioRecord.RECORDSTATE_RECORDING) input.stop()
                } finally {
                    input.release()
                }
            }
        } finally {
            recorder = null
            synchronized(outputGuard) {
                track?.let { output ->
                    try {
                        output.stop()
                    } finally {
                        output.release()
                    }
                }
                track = null
            }
        }
    }

    private data class Chunk(val bytes: ByteArray, val generation: Int)
}
