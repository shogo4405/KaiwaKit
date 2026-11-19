package com.haishinkit.kaiwakit.sample

import com.haishinkit.kaiwakit.conversation.ConversationProvider

internal enum class CredentialKind {
    API_KEY,
    CLIENT_SECRET,
    ;

    fun label(provider: ConversationProvider): String =
        if (this == API_KEY) {
            "API key (local development)"
        } else if (provider == ConversationProvider.OPENAI) {
            "Realtime client secret"
        } else {
            "Ephemeral token"
        }

    fun fieldLabel(provider: ConversationProvider): String = if (this == API_KEY) "${provider.displayName} API key" else label(provider)
}
