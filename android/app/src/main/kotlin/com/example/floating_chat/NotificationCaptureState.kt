package com.example.floating_chat

object NotificationCaptureState {
    fun hasConversationContent(title: String, message: String): Boolean =
        title.isNotBlank() || message.isNotBlank()

    fun noSourceSessionState(stageCode: String?, reasonCode: String?): String = when {
        stageCode == null -> "NO_CAPTURE_EVENT_FOR_SOURCE_APP"
        stageCode == "FILTERED" -> "SOURCE_NOTIFICATION_FILTERED"
        stageCode == "REJECTED" -> "SOURCE_NOTIFICATION_REJECTED"
        reasonCode == "NOT_REPLY_CAPABLE" -> "SOURCE_NOTIFICATION_NOT_REPLY_CAPABLE"
        else -> "NO_REPLY_SESSION_FOR_SOURCE_APP"
    }
}
