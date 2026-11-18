package com.haishinkit.kaiwakit

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class RealtimeEventTest {
    @Test fun decodesJapaneseTranscriptAndIgnoresExtraFields() {
        val event = RealtimeEvent.parse("""{"type":"response.output_audio_transcript.done","transcript":"こんにちは 🎙️","future":true}""")
        assertEquals("こんにちは 🎙️", event.transcript)
        assertNull(event.delta)
    }

    @Test fun acceptsNonMessageItemsAndPreservesUnknownFields() {
        val event = RealtimeEvent.parse("""{"type":"response.output_item.done","item":{"type":"function_call","name":"weather"}}""")
        assertEquals("response.output_item.done", event.type)
        assertNull(event.transcript)
    }

    @Test fun rejectsMissingTypeAndNonObjectEvents() {
        assertThrows(IllegalArgumentException::class.java) { RealtimeEvent.parse("{}") }
        assertThrows(IllegalArgumentException::class.java) { RealtimeEvent.parse("[]") }
    }
}
