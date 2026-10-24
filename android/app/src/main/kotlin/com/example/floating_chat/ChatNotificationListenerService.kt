package com.example.floating_chat

import android.app.Notification
import android.app.PendingIntent
import android.app.Person
import android.app.RemoteInput
import android.content.Context
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.ConcurrentHashMap
import java.security.MessageDigest

class ChatNotificationListenerService : NotificationListenerService() {

    data class NotificationSession(
        val id: String,
        val appName: String,
        val packageName: String,
        val title: String,
        val senderName: String?,
        val text: String,
        val timestamp: Long,
        val direction: String,
        val conversationId: String,
        val notificationPostTime: Long,
        val notificationActive: Boolean,
        val removedAt: Long?,
        val avatar: Bitmap?,
        val contentIntent: PendingIntent?,
        val replyAction: Notification.Action?,
        val replyRemoteInput: RemoteInput?,
        val replyRemoteInputs: Array<RemoteInput>
    )

    data class ReplyAttempt(val accepted: Boolean, val code: String)

    data class CaptureDiagnostic(
        val packageName: String,
        val stageCode: String,
        val reasonCode: String,
        val actionCount: Int,
        val remoteInputActionCount: Int,
        val freeFormRemoteInputActionCount: Int,
        val sessionStored: Boolean,
        val observedAt: Long
    )

    companion object {
        private const val TAG = "ChatNotifListener"

        @Volatile
        var isListenerConnected: Boolean = false
            private set

        // Target package mappings for Phase 2 & 3
        val TARGET_PACKAGES = mapOf(
            "com.whatsapp" to "WhatsApp",
            "com.whatsapp.w4b" to "WhatsApp Business",
            "org.telegram.messenger" to "Telegram",
            "org.telegram.messenger.web" to "Telegram",
            "com.facebook.orca" to "Messenger",
            "com.Slack" to "Slack"
        )

        // In-memory buffer for recent notifications (temporary development display)
        val recentEvents = CopyOnWriteArrayList<Map<String, Any>>()

        // Active session holding reply action & avatar for the floating bubble
        var latestSession: NotificationSession? = null
            private set

        // Active notification-backed conversations available to the overlay service.
        val activeSessions = ConcurrentHashMap<String, NotificationSession>()

        // Safe diagnostic state only. Values are machine-readable result codes;
        // message text and contact details are never stored here.
        val lastReplyAttemptCodes = ConcurrentHashMap<String, String>()

        // One safe capture-stage snapshot per source package. It contains no
        // notification text, title, contact, action label, or RemoteInput data.
        val captureDiagnostics = ConcurrentHashMap<String, CaptureDiagnostic>()

        const val CAPTURE_DIAGNOSTIC_SCHEMA = "capture-v3"

        // Callback hook for active MainActivity
        var onNotificationCallback: ((Map<String, Any>) -> Unit)? = null

        fun clearEvents() {
            recentEvents.clear()
            latestSession = null
            activeSessions.clear()
            lastReplyAttemptCodes.clear()
            captureDiagnostics.clear()
        }

        fun sendQuickReply(
            context: Context,
            session: NotificationSession,
            replyText: String
        ): ReplyAttempt {
            val action = session.replyAction ?: run {
                lastReplyAttemptCodes[session.conversationId] = "REPLY_ACTION_MISSING"
                return ReplyAttempt(false, "REPLY_ACTION_MISSING")
            }
            val remoteInput = session.replyRemoteInput ?: run {
                lastReplyAttemptCodes[session.conversationId] = "REMOTE_INPUT_MISSING"
                return ReplyAttempt(false, "REMOTE_INPUT_MISSING")
            }
            if (!isListenerConnected) {
                lastReplyAttemptCodes[session.conversationId] = "LISTENER_DISCONNECTED"
                Log.w(
                    TAG,
                    "reply_attempt code=LISTENER_DISCONNECTED pkg=${session.packageName} conversation=${safeFingerprint(session.conversationId)}"
                )
                return ReplyAttempt(false, "LISTENER_DISCONNECTED")
            }

            return try {
                val intent = android.content.Intent()
                val bundle = Bundle()
                bundle.putCharSequence(remoteInput.resultKey, replyText)
                RemoteInput.addResultsToIntent(session.replyRemoteInputs, intent, bundle)
                action.actionIntent.send(context, 0, intent)
                Log.i(
                    TAG,
                    "reply_attempt code=ACCEPTED pkg=${session.packageName} conversation=${safeFingerprint(session.conversationId)}"
                )
                lastReplyAttemptCodes[session.conversationId] = "ACCEPTED"
                ReplyAttempt(true, "ACCEPTED")
            } catch (e: PendingIntent.CanceledException) {
                activeSessions.remove(session.id, session)
                lastReplyAttemptCodes[session.conversationId] = "PENDING_INTENT_CANCELED"
                Log.w(
                    TAG,
                    "reply_attempt code=PENDING_INTENT_CANCELED pkg=${session.packageName} conversation=${safeFingerprint(session.conversationId)}"
                )
                ReplyAttempt(false, "PENDING_INTENT_CANCELED")
            } catch (e: Exception) {
                lastReplyAttemptCodes[session.conversationId] = "SEND_EXCEPTION"
                Log.e(
                    TAG,
                    "reply_attempt code=SEND_EXCEPTION pkg=${session.packageName} conversation=${safeFingerprint(session.conversationId)} type=${e.javaClass.simpleName}"
                )
                ReplyAttempt(false, "SEND_EXCEPTION")
            }
        }

        fun safeFingerprint(value: String): String = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray())
            .take(6)
            .joinToString("") { "%02x".format(it) }
    }

    private fun recordCaptureDiagnostic(
        packageName: String,
        stageCode: String,
        reasonCode: String,
        actionCount: Int = -1,
        remoteInputActionCount: Int = -1,
        freeFormRemoteInputActionCount: Int = -1,
        sessionStored: Boolean = false
    ) {
        val diagnostic = CaptureDiagnostic(
            packageName = packageName,
            stageCode = stageCode,
            reasonCode = reasonCode,
            actionCount = actionCount,
            remoteInputActionCount = remoteInputActionCount,
            freeFormRemoteInputActionCount = freeFormRemoteInputActionCount,
            sessionStored = sessionStored,
            observedAt = System.currentTimeMillis()
        )
        captureDiagnostics[packageName] = diagnostic
        Log.i(
            TAG,
            "capture stage=$stageCode reason=$reasonCode pkg=$packageName actions=$actionCount remoteInputActions=$remoteInputActionCount freeFormActions=$freeFormRemoteInputActionCount stored=$sessionStored"
        )
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        isListenerConnected = true
        Log.i(TAG, "NotificationListenerService connected and active")
        try {
            activeNotifications?.forEach { onNotificationPosted(it) }
        } catch (e: Exception) {
            Log.w(TAG, "Could not restore active notification sessions: ${e.javaClass.simpleName}")
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        isListenerConnected = false
        Log.i(TAG, "NotificationListenerService disconnected")
        val expiredSessions = activeSessions.values.toList()
        activeSessions.clear()
        latestSession = null
        expiredSessions.forEach { session ->
            try {
                FloatingBubbleService.onNotificationDismissed(session.id)
            } catch (_: Exception) {
                // The overlay may already be stopped while notification access disconnects.
            }
            val conversationId = session.conversationId
            try {
                onNotificationCallback?.invoke(
                    mapOf(
                        "id" to session.id,
                        "eventType" to "removed",
                        "conversationId" to conversationId,
                        "packageName" to session.packageName,
                        "title" to session.title,
                        "hasReplyAction" to false
                    )
                )
            } catch (_: Exception) {
                // MainActivity may no longer be attached.
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val pkgName = sbn.packageName ?: return
        val notificationKeyFingerprint = safeFingerprint(
            sbn.key ?: "$pkgName:${sbn.id}:${sbn.postTime}"
        )
        Log.i(
            TAG,
            "capture stage=CALLBACK_RECEIVED pkg=$pkgName key=$notificationKeyFingerprint"
        )
        recordCaptureDiagnostic(pkgName, "RECEIVED", "CALLBACK_RECEIVED")
        if (pkgName == packageName) {
            recordCaptureDiagnostic(pkgName, "FILTERED", "SELF_NOTIFICATION")
            return
        }
        val sourceMode = HomePreferences.sourceMode(this)
        if (
            sourceMode == HomePreferences.MODE_CUSTOM &&
            !HomePreferences.selectedPackages(this).contains(pkgName)
        ) {
            Log.i(
                TAG,
                "capture stage=PACKAGE_FILTER result=REJECTED mode=$sourceMode selected=false pkg=$pkgName key=$notificationKeyFingerprint"
            )
            recordCaptureDiagnostic(pkgName, "FILTERED", "NOT_SELECTED_IN_CUSTOM_MODE")
            return
        }
        val appName = TARGET_PACKAGES[pkgName]
            ?: if (sourceMode == HomePreferences.MODE_CUSTOM) {
                runCatching {
                    packageManager.getApplicationLabel(
                        packageManager.getApplicationInfo(pkgName, 0)
                    ).toString()
                }.getOrDefault(pkgName)
            } else {
                Log.i(
                    TAG,
                    "capture stage=PACKAGE_FILTER result=REJECTED mode=$sourceMode supported=false pkg=$pkgName key=$notificationKeyFingerprint"
                )
                recordCaptureDiagnostic(pkgName, "FILTERED", "UNSUPPORTED_IN_ALL_APPS_MODE")
                return
            }
        Log.i(
            TAG,
            "capture stage=PACKAGE_FILTER result=ACCEPTED mode=$sourceMode pkg=$pkgName key=$notificationKeyFingerprint"
        )

        val notification = sbn.notification
        if (notification == null) {
            recordCaptureDiagnostic(pkgName, "REJECTED", "NOTIFICATION_OBJECT_MISSING")
            return
        }
        val actions = notification.actions.orEmpty()
        val remoteInputActionCount = actions.count { !it.remoteInputs.isNullOrEmpty() }
        val freeFormRemoteInputActionCount = actions.count { action ->
            action.remoteInputs?.any { it.allowFreeFormInput } == true
        }
        val replyCandidate = findReplyCandidate(actions)
        recordCaptureDiagnostic(
            packageName = pkgName,
            stageCode = "ACTIONS_INSPECTED",
            reasonCode = when {
                actions.isEmpty() -> "NO_NOTIFICATION_ACTIONS"
                remoteInputActionCount == 0 -> "NO_REMOTE_INPUT_ACTION"
                freeFormRemoteInputActionCount == 0 -> "NO_FREE_FORM_REMOTE_INPUT"
                replyCandidate == null -> "NO_REPLY_CANDIDATE"
                else -> "FREE_FORM_REPLY_DISCOVERED"
            },
            actionCount = actions.size,
            remoteInputActionCount = remoteInputActionCount,
            freeFormRemoteInputActionCount = freeFormRemoteInputActionCount
        )

        // Ignore ongoing notifications (like calls or background transfers)
        if (sbn.isOngoing && replyCandidate == null) {
            recordCaptureDiagnostic(
                pkgName,
                "FILTERED",
                "ONGOING_NOTIFICATION",
                actions.size,
                remoteInputActionCount,
                freeFormRemoteInputActionCount
            )
            return
        }
        if (sbn.isOngoing) {
            Log.i(
                TAG,
                "capture stage=FILTER_BYPASSED reason=ONGOING_WITH_FREE_FORM_REPLY pkg=$pkgName key=$notificationKeyFingerprint"
            )
        }

        // Ignore group summary notifications
        val isGroupSummary = (notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0
        if (isGroupSummary && replyCandidate == null) {
            recordCaptureDiagnostic(
                pkgName,
                "FILTERED",
                "GROUP_SUMMARY",
                actions.size,
                remoteInputActionCount,
                freeFormRemoteInputActionCount
            )
            return
        }
        if (isGroupSummary) {
            Log.i(
                TAG,
                "capture stage=FILTER_BYPASSED reason=GROUP_SUMMARY_WITH_FREE_FORM_REPLY pkg=$pkgName key=$notificationKeyFingerprint"
            )
        }

        val extras = notification.extras
        if (extras == null) {
            recordCaptureDiagnostic(
                pkgName,
                "REJECTED",
                "EXTRAS_MISSING",
                actions.size,
                remoteInputActionCount,
                freeFormRemoteInputActionCount
            )
            return
        }

        // Extract Title (usually sender or group name)
        var title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        if (title.isEmpty()) {
            title = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)
                ?.toString()
                ?.trim()
                .orEmpty()
        }

        // Extract Text (message body)
        var message = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim() ?: ""
        if (message.isEmpty()) {
            message = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim() ?: ""
        }

        // MessagingStyle may carry the only available title/message. Parse it
        // before deciding that a notification has no conversation content.
        var senderName: String? = null
        var newestStyledMessage: Notification.MessagingStyle.Message? = null
        try {
            val messageBundles = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
            val styledMessages = Notification.MessagingStyle.Message
                .getMessagesFromBundleArray(messageBundles)
            val newest = styledMessages.lastOrNull()
            newestStyledMessage = newest
            if (newest != null) {
                if (newest.text?.toString()?.isNotBlank() == true) {
                    message = newest.text.toString().trim()
                }
                senderName = newest.senderPerson?.name?.toString()?.trim()
                    ?: @Suppress("DEPRECATION") newest.sender?.toString()?.trim()
                if (title.isEmpty()) title = senderName.orEmpty()
            }
        } catch (_: Exception) {
            // Basic title/text parsing remains available when MessagingStyle data is malformed.
        }

        // WhatsApp can briefly post an app-level sync placeholder before the
        // conversation notification. It is not a message and must not become
        // a separate conversation bubble.
        val isWhatsAppSyncPlaceholder =
            (pkgName == "com.whatsapp" || pkgName == "com.whatsapp.w4b") &&
                title.equals(appName, ignoreCase = true) &&
                message.equals("Checking for new messages", ignoreCase = true)
        if (isWhatsAppSyncPlaceholder) {
            recordCaptureDiagnostic(
                pkgName,
                "FILTERED",
                "WHATSAPP_SYNC_PLACEHOLDER",
                actions.size,
                remoteInputActionCount,
                freeFormRemoteInputActionCount
            )
            return
        }

        if (!NotificationCaptureState.hasConversationContent(title, message)) {
            recordCaptureDiagnostic(
                pkgName,
                "REJECTED",
                "NO_CONVERSATION_CONTENT_AFTER_MESSAGING_STYLE",
                actions.size,
                remoteInputActionCount,
                freeFormRemoteInputActionCount
            )
            return
        }
        Log.i(
            TAG,
            "capture stage=MESSAGE_PARSED result=CONTENT_AVAILABLE pkg=$pkgName key=$notificationKeyFingerprint messagingStyle=${newestStyledMessage != null}"
        )

        val localPerson = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                extras.getParcelable("android.messagingUser", Person::class.java)
            } else {
                @Suppress("DEPRECATION")
                extras.getParcelable("android.messagingUser") as? Person
            }
        } else {
            null
        }
        val localName = localPerson?.name?.toString()?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: extras.getCharSequence("android.selfDisplayName")?.toString()?.trim()
                ?.takeIf { it.isNotEmpty() }
        val senderPerson = newestStyledMessage?.senderPerson
        val localPersonKey = localPerson?.key
        val sameStablePerson = !localPersonKey.isNullOrBlank() &&
            localPersonKey == senderPerson?.key
        val sameNamedPerson = localName != null &&
            !senderName.isNullOrBlank() &&
            localName.equals(senderName, ignoreCase = true)
        val direction = if (sameStablePerson || sameNamedPerson) "outgoing" else "incoming"
        val timestamp = newestStyledMessage?.timestamp?.takeIf { it > 0L }
            ?: sbn.postTime.takeIf { it > 0L }
            ?: System.currentTimeMillis()
        val eventId = sbn.key ?: "$pkgName-$timestamp"

        // Extract Avatar Bitmap if provided
        var avatarBitmap: Bitmap? = null
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val largeIcon = notification.getLargeIcon()
                if (largeIcon != null) {
                    val drawable = largeIcon.loadDrawable(this)
                    if (drawable is BitmapDrawable) {
                        avatarBitmap = drawable.bitmap
                    }
                }
            }
            if (avatarBitmap == null) {
                @Suppress("DEPRECATION")
                avatarBitmap = extras.getParcelable(Notification.EXTRA_LARGE_ICON) as? Bitmap
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not load avatar: ${e.message}")
        }

        val conversationId = ChatHistoryStore.conversationId(pkgName, title, eventId)
        Log.i(
            TAG,
            "capture stage=CONVERSATION_RESOLVED pkg=$pkgName key=$notificationKeyFingerprint conversation=${safeFingerprint(conversationId)}"
        )
        val previousSession = activeSessions[eventId]
        val carryForwardReplyAction = ReplySessionLifecycle.shouldCarryForwardReplyAction(
            sameConversation = previousSession?.conversationId == conversationId,
            currentUpdateHasReplyAction = replyCandidate != null,
            previousSessionHasReplyAction = previousSession?.let {
                it.replyAction != null && it.replyRemoteInput != null
            } == true
        )
        val replyAction = replyCandidate?.action
            ?: previousSession?.replyAction?.takeIf { carryForwardReplyAction }
        val replyRemoteInput = replyCandidate?.remoteInput
            ?: previousSession?.replyRemoteInput?.takeIf { carryForwardReplyAction }
        val replyRemoteInputs = replyCandidate?.action?.remoteInputs
            ?: previousSession?.replyRemoteInputs?.takeIf { carryForwardReplyAction }
            ?: emptyArray()
        val replyActionSource = when {
            replyCandidate != null -> "CURRENT_NOTIFICATION"
            carryForwardReplyAction -> "CARRIED_FORWARD_SAME_NOTIFICATION"
            else -> "NONE"
        }
        lastReplyAttemptCodes.remove(conversationId)
        val session = NotificationSession(
            id = eventId,
            appName = appName,
            packageName = pkgName,
            title = title,
            senderName = senderName,
            text = message,
            timestamp = timestamp,
            direction = direction,
            conversationId = conversationId,
            notificationPostTime = sbn.postTime,
            notificationActive = true,
            removedAt = null,
            avatar = avatarBitmap,
            contentIntent = notification.contentIntent
                ?: previousSession?.contentIntent?.takeIf { carryForwardReplyAction },
            replyAction = replyAction,
            replyRemoteInput = replyRemoteInput,
            replyRemoteInputs = replyRemoteInputs
        )
        latestSession = session
        activeSessions[eventId] = session
        recordCaptureDiagnostic(
            packageName = pkgName,
            stageCode = "SESSION_STORED",
            reasonCode = when {
                replyCandidate != null -> "FREE_FORM_REPLY_SESSION_STORED"
                carryForwardReplyAction -> "CARRIED_FORWARD_REPLY_SESSION_STORED"
                actions.isEmpty() -> "SESSION_STORED_WITHOUT_ACTIONS"
                remoteInputActionCount == 0 -> "SESSION_STORED_WITHOUT_REMOTE_INPUT"
                else -> "SESSION_STORED_WITHOUT_FREE_FORM_REMOTE_INPUT"
            },
            actionCount = actions.size,
            remoteInputActionCount = remoteInputActionCount,
            freeFormRemoteInputActionCount = freeFormRemoteInputActionCount,
            sessionStored = true
        )
        Log.i(
            TAG,
            "notification_posted pkg=$pkgName conversation=${safeFingerprint(conversationId)} actions=${notification.actions?.size ?: 0} freeForm=${replyCandidate != null} selectedAction=${replyCandidate?.actionIndex ?: -1} replyActionSource=$replyActionSource"
        )
        try {
            val persistenceResult = ChatHistoryStore.get(this)
                .recordObservedNotification(session)
            Log.i(
                TAG,
                "capture stage=SQLITE_PERSISTED result=$persistenceResult pkg=$pkgName key=$notificationKeyFingerprint conversation=${safeFingerprint(conversationId)}"
            )
        } catch (e: Exception) {
            Log.e(TAG, "Could not persist notification metadata: ${e.javaClass.simpleName}")
        }

        val eventData = mapOf<String, Any>(
            "id" to eventId,
            "eventType" to "posted",
            "conversationId" to conversationId,
            "appName" to appName,
            "packageName" to pkgName,
            "title" to title,
            "text" to message,
            "timestamp" to timestamp,
            "direction" to direction,
            "hasReplyAction" to (replyAction != null)
        )

        // Keep in-memory list bounded to recent 20
        if (recentEvents.size >= 20) {
            recentEvents.removeAt(0)
        }
        recentEvents.add(eventData)

        // Dispatch to native FloatingBubbleService if active
        try {
            val bubbleDispatch = FloatingBubbleService.onSessionReceived(session)
            Log.i(
                TAG,
                "capture stage=BUBBLE_DISPATCH result=$bubbleDispatch pkg=$pkgName key=$notificationKeyFingerprint conversation=${safeFingerprint(conversationId)}"
            )
        } catch (e: Exception) {
            Log.e(
                TAG,
                "capture stage=BUBBLE_DISPATCH result=FAILED type=${e.javaClass.simpleName} pkg=$pkgName key=$notificationKeyFingerprint"
            )
        }

        // Dispatch to active Flutter app if open
        try {
            val callback = onNotificationCallback
            if (callback == null) {
                Log.i(
                    TAG,
                    "capture stage=FLUTTER_EVENT result=NO_ACTIVE_ENGINE pkg=$pkgName key=$notificationKeyFingerprint conversation=${safeFingerprint(conversationId)}"
                )
            } else {
                callback.invoke(eventData)
                Log.i(
                    TAG,
                    "capture stage=FLUTTER_EVENT result=DISPATCHED pkg=$pkgName key=$notificationKeyFingerprint conversation=${safeFingerprint(conversationId)}"
                )
            }
        } catch (e: Exception) {
            Log.e(
                TAG,
                "capture stage=FLUTTER_EVENT result=FAILED type=${e.javaClass.simpleName} pkg=$pkgName key=$notificationKeyFingerprint"
            )
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        if (sbn == null) return

        val key = sbn.key
        if (key != null) {
            var removedSession: NotificationSession? = null
            var retainedReplySession = false
            var newerReplacementRetained = false
            activeSessions.computeIfPresent(key) { _, current ->
                if (
                    ReplySessionLifecycle.shouldIgnoreRemoval(
                        current.notificationPostTime,
                        sbn.postTime
                    )
                ) {
                    newerReplacementRetained = true
                    current
                } else {
                    removedSession = current
                    if (
                        ReplySessionLifecycle.shouldRetainReplySessionOnRemoval(
                            hasReplyAction = current.replyAction != null,
                            hasRemoteInput = current.replyRemoteInput != null
                        )
                    ) {
                        retainedReplySession = true
                        current.copy(
                            notificationActive = false,
                            removedAt = System.currentTimeMillis()
                        )
                    } else {
                        null
                    }
                }
            }
            if (newerReplacementRetained) {
                Log.i(
                    TAG,
                    "notification_removed code=STALE_REMOVAL_IGNORED pkg=${sbn.packageName} key=${safeFingerprint(key)}"
                )
                return
            }
            if (latestSession?.id == key) {
                latestSession = activeSessions.values
                    .filter { it.notificationActive }
                    .maxByOrNull { it.timestamp }
            }
            try {
                FloatingBubbleService.onNotificationDismissed(key)
            } catch (e: Exception) {
                Log.e(TAG, "Error notifying FloatingBubbleService of dismissal: ${e.message}")
            }

            val iterator = recentEvents.iterator()
            while (iterator.hasNext()) {
                val item = iterator.next()
                if (item["id"] == key) {
                    recentEvents.remove(item)
                    break
                }
            }
            removedSession?.let { removed ->
                val conversationId = removed.conversationId
                Log.i(
                    TAG,
                    "notification_removed code=${if (retainedReplySession) "REPLY_SESSION_RETAINED" else "SESSION_EXPIRED"} pkg=${removed.packageName} conversation=${safeFingerprint(conversationId)}"
                )
                recordCaptureDiagnostic(
                    packageName = removed.packageName,
                    stageCode = if (retainedReplySession) {
                        "SESSION_RETAINED"
                    } else {
                        "SESSION_REMOVED"
                    },
                    reasonCode = if (retainedReplySession) {
                        "CAPTURED_REPLY_ACTION_RETAINED"
                    } else {
                        "NOT_REPLY_CAPABLE"
                    },
                    remoteInputActionCount = if (removed.replyRemoteInputs.isNotEmpty()) 1 else 0,
                    freeFormRemoteInputActionCount = if (removed.replyRemoteInput != null) 1 else 0,
                    sessionStored = retainedReplySession
                )
                try {
                    onNotificationCallback?.invoke(
                        mapOf(
                            "id" to key,
                            "eventType" to "removed",
                            "conversationId" to conversationId,
                            "packageName" to removed.packageName,
                            "title" to removed.title,
                            "hasReplyAction" to false
                        )
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "Error invoking notification removal callback: ${e.message}")
                }
            }
        }
    }

    private data class ReplyCandidate(
        val action: Notification.Action,
        val remoteInput: RemoteInput,
        val actionIndex: Int,
        val priority: Int
    )

    private fun findReplyCandidate(actions: Array<out Notification.Action>): ReplyCandidate? =
        actions
            .mapIndexedNotNull { index, action ->
                val freeFormInput = action.remoteInputs
                    ?.firstOrNull { it.allowFreeFormInput }
                    ?: return@mapIndexedNotNull null
                val semanticReply = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                    action.semanticAction == Notification.Action.SEMANTIC_ACTION_REPLY
                val replyLabel = action.title?.toString()?.trim()?.lowercase().orEmpty()
                val labelLooksLikeReply = replyLabel.contains("reply") ||
                    replyLabel.contains("respond")
                ReplyCandidate(
                    action = action,
                    remoteInput = freeFormInput,
                    actionIndex = index,
                    priority = when {
                        semanticReply -> 2
                        labelLooksLikeReply -> 1
                        else -> 0
                    }
                )
            }
            .maxWithOrNull(
                compareBy<ReplyCandidate> { it.priority }
                    .thenByDescending { -it.actionIndex }
            )
}
