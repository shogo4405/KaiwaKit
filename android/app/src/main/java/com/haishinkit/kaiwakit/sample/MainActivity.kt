package com.haishinkit.kaiwakit.sample

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp

class MainActivity : ComponentActivity() {
    private lateinit var conversation: ConversationController

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        conversation = ConversationController(applicationContext)
        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize()) {
                    var secret by remember { mutableStateOf("") }
                    var permissionDenied by remember { mutableStateOf(false) }
                    val microphonePermission =
                        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
                            permissionDenied = !granted
                            // Do not begin a call from a late permission result after backgrounding.
                            if (granted && lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) {
                                conversation.start(secret.trim())
                            }
                        }
                    Column(
                        Modifier.padding(24.dp).verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Text("Kaiwa", style = MaterialTheme.typography.headlineLarge)
                        Text("Use headphones for this prototype. Calls end when you leave this screen.")
                        OutlinedTextField(
                            value = secret,
                            onValueChange = { secret = it },
                            label = { Text("Realtime client secret") },
                            visualTransformation = PasswordVisualTransformation(),
                            enabled = !conversation.active,
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Text(if (permissionDenied) "Microphone permission is required." else conversation.status)
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Button(
                                enabled = secret.isNotBlank() || conversation.active,
                                onClick = {
                                    if (conversation.active) {
                                        conversation.stop()
                                    } else if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                                        conversation.start(secret.trim())
                                    } else {
                                        microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
                                    }
                                },
                            ) { Text(if (conversation.active) "Stop" else "Start conversation") }
                            Button(enabled = conversation.active, onClick = conversation::toggleMute) {
                                Text(if (conversation.muted) "Unmute" else "Mute")
                            }
                        }
                        Text(conversation.transcript.ifBlank { "Conversation transcripts will appear here." })
                    }
                }
            }
        }
    }

    override fun onStop() {
        conversation.stop()
        super.onStop()
    }

    override fun onDestroy() {
        conversation.dispose()
        super.onDestroy()
    }
}
