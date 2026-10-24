package com.example.floating_chat

object ReplySessionLifecycle {
    fun shouldIgnoreRemoval(
        currentNotificationPostTime: Long,
        removedNotificationPostTime: Long
    ): Boolean = currentNotificationPostTime > removedNotificationPostTime

    fun shouldCarryForwardReplyAction(
        sameConversation: Boolean,
        currentUpdateHasReplyAction: Boolean,
        previousSessionHasReplyAction: Boolean
    ): Boolean = sameConversation &&
        !currentUpdateHasReplyAction &&
        previousSessionHasReplyAction

    fun shouldRetainReplySessionOnRemoval(
        hasReplyAction: Boolean,
        hasRemoteInput: Boolean
    ): Boolean = hasReplyAction && hasRemoteInput
}
