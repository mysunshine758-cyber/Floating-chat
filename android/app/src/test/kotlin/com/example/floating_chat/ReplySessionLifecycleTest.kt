package com.example.floating_chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReplySessionLifecycleTest {
    @Test
    fun olderRemovalCannotExpireNewerReplacement() {
        assertTrue(
            ReplySessionLifecycle.shouldIgnoreRemoval(
                currentNotificationPostTime = 2_000L,
                removedNotificationPostTime = 1_000L
            )
        )
    }

    @Test
    fun currentNotificationRemovalExpiresItsSession() {
        assertFalse(
            ReplySessionLifecycle.shouldIgnoreRemoval(
                currentNotificationPostTime = 2_000L,
                removedNotificationPostTime = 2_000L
            )
        )
    }

    @Test
    fun actionlessUpdateKeepsReplyActionForSameConversation() {
        assertTrue(
            ReplySessionLifecycle.shouldCarryForwardReplyAction(
                sameConversation = true,
                currentUpdateHasReplyAction = false,
                previousSessionHasReplyAction = true
            )
        )
    }

    @Test
    fun actionIsNotCarriedAcrossConversationIdentityChange() {
        assertFalse(
            ReplySessionLifecycle.shouldCarryForwardReplyAction(
                sameConversation = false,
                currentUpdateHasReplyAction = false,
                previousSessionHasReplyAction = true
            )
        )
    }

    @Test
    fun currentReplyActionAlwaysReplacesPreviousAction() {
        assertFalse(
            ReplySessionLifecycle.shouldCarryForwardReplyAction(
                sameConversation = true,
                currentUpdateHasReplyAction = true,
                previousSessionHasReplyAction = true
            )
        )
    }

    @Test
    fun notificationRemovalRetainsCapturedFreeFormReplySession() {
        assertTrue(
            ReplySessionLifecycle.shouldRetainReplySessionOnRemoval(
                hasReplyAction = true,
                hasRemoteInput = true
            )
        )
    }

    @Test
    fun notificationRemovalDropsSessionWithoutRemoteInput() {
        assertFalse(
            ReplySessionLifecycle.shouldRetainReplySessionOnRemoval(
                hasReplyAction = true,
                hasRemoteInput = false
            )
        )
    }
}
