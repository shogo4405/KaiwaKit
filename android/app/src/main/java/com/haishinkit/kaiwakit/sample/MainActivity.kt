package com.haishinkit.kaiwakit.sample

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
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
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import com.haishinkit.kaiwakit.conversation.ConversationProvider
import com.haishinkit.kaiwakit.gemini.GeminiSessionConfiguration

class MainActivity : ComponentActivity() {
    private lateinit var conversation: ConversationController

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        conversation = ConversationController(applicationContext)
        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize()) {
                    var provider by remember { mutableStateOf(ConversationProvider.OPENAI) }
                    var model by remember { mutableStateOf(GeminiSessionConfiguration.DEFAULT_MODEL) }
                    var credentialKind by remember { mutableStateOf(CredentialKind.API_KEY) }
                    var credential by remember { mutableStateOf("") }
                    var permissionDenied by remember { mutableStateOf(false) }
                    var browserUnavailable by remember { mutableStateOf(false) }
                    var showSignInInfo by remember { mutableStateOf(false) }
                    val microphonePermission =
                        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
                            permissionDenied = !granted
                            // Do not begin a call from a late permission result after backgrounding.
                            if (granted && lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) {
                                conversation.start(credential.trim(), credentialKind, provider, model)
                            }
                        }
                    Column(
                        Modifier.padding(24.dp).verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Text("Kaiwa", style = MaterialTheme.typography.headlineLarge)
                        Text("Use headphones for this prototype. Calls end when you leave this screen.")
                        Text("AI service", style = MaterialTheme.typography.titleMedium)
                        Row(Modifier.selectableGroup()) {
                            ConversationProvider.entries.forEach { choice ->
                                Row(
                                    Modifier.weight(1f).selectable(
                                        selected = provider == choice,
                                        enabled = !conversation.active,
                                        role = Role.RadioButton,
                                        onClick = {
                                            if (provider != choice) {
                                                provider = choice
                                                credential = ""
                                                credentialKind = CredentialKind.API_KEY
                                                showSignInInfo = false
                                                browserUnavailable = false
                                            }
                                        },
                                    ),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    RadioButton(selected = provider == choice, onClick = null, enabled = !conversation.active)
                                    Text(choice.displayName)
                                }
                            }
                        }
                        if (provider == ConversationProvider.GEMINI) {
                            OutlinedTextField(
                                value = model,
                                onValueChange = { model = it },
                                label = { Text("Gemini Live model") },
                                singleLine = true,
                                enabled = !conversation.active,
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                        Text("${provider.displayName} connection", style = MaterialTheme.typography.titleMedium)
                        Column(Modifier.selectableGroup()) {
                            CredentialKind.entries.forEach { kind ->
                                Row(
                                    Modifier.fillMaxWidth().selectable(
                                        selected = credentialKind == kind,
                                        enabled = !conversation.active,
                                        role = Role.RadioButton,
                                        onClick = {
                                            if (credentialKind != kind) {
                                                credentialKind = kind
                                                credential = ""
                                            }
                                        },
                                    ).padding(vertical = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    RadioButton(selected = credentialKind == kind, onClick = null, enabled = !conversation.active)
                                    Text(kind.label(provider), modifier = Modifier.padding(start = 12.dp))
                                }
                            }
                        }
                        OutlinedTextField(
                            value = credential,
                            onValueChange = { credential = it },
                            label = { Text(credentialKind.fieldLabel(provider)) },
                            supportingText = {
                                Text(
                                    if (credentialKind == CredentialKind.API_KEY) {
                                        "Paste a key from your ${provider.displayName} API account."
                                    } else {
                                        "Paste a fresh client secret from your backend."
                                    },
                                )
                            },
                            visualTransformation = PasswordVisualTransformation(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                            enabled = !conversation.active,
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Text(
                            "Credentials stay in memory. API usage is billed separately from ChatGPT.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        TextButton(
                            enabled = !conversation.active,
                            onClick = {
                                try {
                                    startActivity(
                                        Intent(
                                            Intent.ACTION_VIEW,
                                            (
                                                if (provider == ConversationProvider.OPENAI) {
                                                    "https://platform.openai.com/api-keys"
                                                } else {
                                                    "https://aistudio.google.com/apikey"
                                                }
                                            ).toUri(),
                                        ),
                                    )
                                    browserUnavailable = false
                                } catch (_: ActivityNotFoundException) {
                                    browserUnavailable = true
                                }
                            },
                        ) { Text("Open ${provider.displayName} API keys") }
                        if (browserUnavailable) {
                            Text("No browser is available. Open your service’s API-key page on another device.")
                        }
                        if (provider == ConversationProvider.OPENAI) {
                            TextButton(
                                onClick = { showSignInInfo = !showSignInInfo },
                            ) { Text("About ChatGPT sign-in") }
                        }
                        if (provider == ConversationProvider.OPENAI && showSignInInfo) {
                            Text(
                                "Sign in to OpenAI in your browser to create an API key, then paste it here. " +
                                    "The documented ChatGPT sign-in flow covers the Responses API; " +
                                    "Realtime voice access is not confirmed for that flow.",
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                        Text(if (permissionDenied) "Microphone permission is required." else conversation.status)
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Button(
                                enabled =
                                    conversation.active ||
                                        (
                                            credential.isNotBlank() &&
                                                (provider != ConversationProvider.GEMINI || model.isNotBlank())
                                        ),
                                onClick = {
                                    if (conversation.active) {
                                        conversation.stop()
                                    } else if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                                        permissionDenied = false
                                        conversation.start(credential.trim(), credentialKind, provider, model)
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
