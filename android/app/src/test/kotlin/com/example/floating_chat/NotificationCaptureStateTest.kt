package com.example.floating_chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationCaptureStateTest {
    @Test
    fun messagingStyleContentPreventsPrematureRejection() {
        assertTrue(
            NotificationCaptureState.hasConversationContent(
                title = "",
                message = "Message extracted from MessagingStyle"
            )
        )
    }

    @Test
    fun emptyConversationContentIsRejectedAfterAllExtraction() {
        assertFalse(NotificationCaptureState.hasConversationContent("", ""))
    }

    @Test
    fun missingCaptureEventHasDistinctState() {
        assertEquals(
            "NO_CAPTURE_EVENT_FOR_SOURCE_APP",
            NotificationCaptureState.noSourceSessionState(null, null)
        )
    }

    @Test
    fun filteredAndRejectedEventsRemainDistinguishable() {
        assertEquals(
            "SOURCE_NOTIFICATION_FILTERED",
            NotificationCaptureState.noSourceSessionState(
                "FILTERED",
                "NOT_SELECTED_IN_CUSTOM_MODE"
            )
        )
        assertEquals(
            "SOURCE_NOTIFICATION_REJECTED",
            NotificationCaptureState.noSourceSessionState(
                "REJECTED",
                "NO_CONVERSATION_CONTENT_AFTER_MESSAGING_STYLE"
            )
        )
    }
}
