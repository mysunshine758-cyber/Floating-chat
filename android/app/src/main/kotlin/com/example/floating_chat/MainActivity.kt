package com.example.floating_chat

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.provider.OpenableColumns
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.floating_chat/bubble"
    private val TAG = "FloatingChatReply"
    private var methodChannel: MethodChannel? = null
    private var pendingFileResult: MethodChannel.Result? = null
    private var pendingAttachmentResult: MethodChannel.Result? = null
    private var pendingVoicePermissionResult: MethodChannel.Result? = null
    private var mediaRecorder: MediaRecorder? = null
    private var voiceRecordingFile: File? = null
    private var voiceRecordingStartedAt: Long = 0L
    private var voicePreviewPlayer: MediaPlayer? = null
    private val managedComposerFiles = mutableMapOf<String, File>()

    companion object {
        private const val REQUEST_EXPORT_HISTORY = 4101
        private const val REQUEST_IMPORT_HISTORY = 4102
        private const val REQUEST_PICK_ATTACHMENT = 4103
        private const val REQUEST_RECORD_AUDIO_PERMISSION = 4104
        private const val MAX_ATTACHMENT_BYTES = 25L * 1024L * 1024L
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        // Hook up real-time notification forwarding to Flutter
        ChatNotificationListenerService.onNotificationCallback = { event ->
            runOnUiThread {
                val eventPackage = event["packageName"]?.toString().orEmpty()
                val conversationFingerprint = event["conversationId"]
                    ?.toString()
                    ?.let(ChatNotificationListenerService::safeFingerprint)
                    ?: "none"
                Log.i(
                    TAG,
                    "flutter_event stage=EMIT pkg=$eventPackage conversation=$conversationFingerprint"
                )
                channel.invokeMethod(
                    "onNotificationReceived",
                    event,
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            Log.i(
                                TAG,
                                "flutter_event stage=RECEIVED pkg=$eventPackage conversation=$conversationFingerprint"
                            )
                        }

                        override fun error(
                            errorCode: String,
                            errorMessage: String?,
                            errorDetails: Any?
                        ) {
                            Log.w(
                                TAG,
                                "flutter_event stage=FAILED code=$errorCode pkg=$eventPackage conversation=$conversationFingerprint"
                            )
                        }

                        override fun notImplemented() {
                            Log.w(
                                TAG,
                                "flutter_event stage=NO_DART_HANDLER pkg=$eventPackage conversation=$conversationFingerprint"
                            )
                        }
                    }
                )
            }
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkOverlayPermission" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "requestOverlayPermission" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    ).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                    result.success(true)
                }
                "checkNotificationPermission" -> {
                    result.success(isNotificationAccessGranted())
                }
                "requestNotificationPermission" -> {
                    val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                    result.success(true)
                }
                "getRecentNotifications" -> {
                    result.success(ChatNotificationListenerService.recentEvents.toList())
                }
                "getConversationSummaries" -> {
                    try {
                        result.success(loadConversationSummaries())
                    } catch (e: Exception) {
                        result.error(
                            "CONVERSATIONS_FAILED",
                            "Could not load local conversations",
                            e.javaClass.simpleName
                        )
                    }
                }
                "getConversationDetails" -> {
                    try {
                        val conversationId = call.argument<String>("conversationId")
                            ?.takeIf { it.isNotBlank() }
                            ?: error("Missing conversation id")
                        result.success(loadConversationDetails(conversationId))
                    } catch (e: IllegalStateException) {
                        result.error("INVALID_CONVERSATION", e.message, null)
                    } catch (e: Exception) {
                        result.error(
                            "CONVERSATION_FAILED",
                            "Could not load this conversation",
                            e.javaClass.simpleName
                        )
                    }
                }
                "getConversationReplyCapability" -> {
                    try {
                        val conversationId = call.argument<String>("conversationId")
                            ?.takeIf { it.isNotBlank() }
                            ?: error("Missing conversation id")
                        result.success(replyCapability(conversationId))
                    } catch (e: IllegalStateException) {
                        result.error("INVALID_CONVERSATION", e.message, null)
                    } catch (e: Exception) {
                        result.error(
                            "CAPABILITY_CHECK_FAILED",
                            "Could not verify the current reply capability.",
                            e.javaClass.simpleName
                        )
                    }
                }
                "sendConversationReply" -> {
                    try {
                        val conversationId = call.argument<String>("conversationId")
                            ?.takeIf { it.isNotBlank() }
                            ?: error("Missing conversation id")
                        val text = call.argument<String>("text")
                            ?.trim()
                            ?.takeIf { it.isNotEmpty() }
                            ?: error("Reply cannot be empty")
                        val session = activeSessionsForConversation(conversationId)
                            .filter {
                                it.replyAction != null && it.replyRemoteInput != null
                            }
                            .maxByOrNull { it.timestamp }
                        if (session == null) {
                            val capability = replyCapability(conversationId)
                            result.error(
                                capability["stateCode"]?.toString() ?: "REPLY_UNAVAILABLE",
                                capability["replyUnavailableReason"]?.toString()
                                    ?: "The notification reply action is no longer available.",
                                mapOf("stateCode" to capability["stateCode"])
                            )
                        } else {
                            val attempt = ChatNotificationListenerService.sendQuickReply(
                                this,
                                session,
                                text
                            )
                            if (attempt.accepted) {
                            val timestamp = System.currentTimeMillis()
                            val replyStatus = "submitted; delivery unconfirmed"
                            ChatHistoryStore.get(this).recordOutgoing(
                                conversationId,
                                text,
                                timestamp,
                                replyStatus
                            )
                            result.success(
                                mapOf(
                                    "accepted" to true,
                                    "timestamp" to timestamp,
                                    "replyStatus" to replyStatus
                                )
                            )
                            } else {
                                val message = when (attempt.code) {
                                    "LISTENER_DISCONNECTED" ->
                                        "Notification access is enabled, but the listener is disconnected. Reopen notification access settings or the source app and try again."
                                    "PENDING_INTENT_CANCELED" ->
                                        "The source app cancelled or replaced this quick-reply action. Your draft was kept."
                                    "REPLY_ACTION_MISSING", "REMOTE_INPUT_MISSING" ->
                                        "This notification does not currently provide a supported quick-reply action."
                                    else ->
                                        "The source app did not accept the notification reply."
                                }
                                result.error(attempt.code, message, null)
                            }
                        }
                    } catch (e: IllegalStateException) {
                        result.error("INVALID_REPLY", e.message, null)
                    } catch (e: Exception) {
                        result.error(
                            "REPLY_FAILED",
                            "Could not send the notification reply.",
                            e.javaClass.simpleName
                        )
                    }
                }
                "openConversation" -> {
                    try {
                        val conversationId = call.argument<String>("conversationId")
                            ?.takeIf { it.isNotBlank() }
                            ?: error("Missing conversation id")
                        val session = activeSessionsForConversation(conversationId)
                            .filter { it.contentIntent != null }
                            .maxByOrNull { it.timestamp }
                        val contentIntent = session?.contentIntent
                        if (contentIntent != null) {
                            contentIntent.send()
                            result.success(true)
                        } else {
                            val sourcePackage = ChatHistoryStore.get(this)
                                .packageNameForConversation(conversationId)
                            val launchIntent = sourcePackage?.let {
                                packageManager.getLaunchIntentForPackage(it)
                            }
                            if (launchIntent != null) {
                                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(launchIntent)
                                result.success(true)
                            } else {
                            result.error(
                                "OPEN_UNAVAILABLE",
                                    "The source messaging app could not be opened.",
                                null
                            )
                            }
                        }
                    } catch (e: IllegalStateException) {
                        result.error("INVALID_CONVERSATION", e.message, null)
                    } catch (e: Exception) {
                        result.error(
                            "OPEN_FAILED",
                            "Could not open the source app.",
                            e.javaClass.simpleName
                        )
                    }
                }
                "pickConversationAttachment" -> {
                    if (pendingAttachmentResult != null || pendingFileResult != null) {
                        result.error("BUSY", "Another file operation is active.", null)
                    } else {
                        pendingAttachmentResult = result
                        val requestedType = call.argument<String>("mimeType")
                            ?.takeIf { it.isNotBlank() }
                            ?: "*/*"
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = requestedType
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivityForResult(intent, REQUEST_PICK_ATTACHMENT)
                    }
                }
                "discardConversationAttachment" -> {
                    val uri = call.argument<String>("uri")
                    val file = uri?.let { managedComposerFiles.remove(it) }
                    if (file != null && file.exists()) file.delete()
                    result.success(true)
                }
                "startVoiceRecording" -> {
                    if (mediaRecorder != null || pendingVoicePermissionResult != null) {
                        result.error("RECORDING_ACTIVE", "A recording is already active.", null)
                    } else if (
                        ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                    ) {
                        startVoiceRecording(result)
                    } else {
                        pendingVoicePermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            REQUEST_RECORD_AUDIO_PERMISSION
                        )
                    }
                }
                "stopVoiceRecording" -> stopVoiceRecording(result)
                "cancelVoiceRecording" -> {
                    cancelVoiceRecording()
                    result.success(true)
                }
                "playVoicePreview" -> {
                    try {
                        val uri = call.argument<String>("uri")
                            ?.takeIf { it.isNotBlank() }
                            ?: error("Missing recording URI")
                        playVoicePreview(Uri.parse(uri))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error(
                            "PLAYBACK_FAILED",
                            "Could not play the voice recording.",
                            e.javaClass.simpleName
                        )
                    }
                }
                "shareConversationAttachment" -> {
                    try {
                        val conversationId = call.argument<String>("conversationId")
                            ?.takeIf { it.isNotBlank() }
                            ?: error("Missing conversation id")
                        val expectedPackage = activeSessionsForConversation(conversationId)
                            .maxByOrNull { it.timestamp }
                            ?.packageName
                        val requestedPackage = call.argument<String>("packageName")
                            ?.takeIf { it.isNotBlank() }
                            ?: error("Missing source package")
                        if (expectedPackage != null && expectedPackage != requestedPackage) {
                            error("Conversation package mismatch")
                        }
                        val uri = call.argument<String>("uri")
                            ?.takeIf { it.isNotBlank() }
                            ?.let(Uri::parse)
                            ?: error("Missing attachment URI")
                        val mimeType = call.argument<String>("mimeType")
                            ?.takeIf { it.isNotBlank() }
                            ?: "application/octet-stream"
                        val text = call.argument<String>("text")?.trim().orEmpty()
                        openExternalShare(requestedPackage, uri, mimeType, text)
                        result.success(true)
                    } catch (e: IllegalStateException) {
                        result.error("SHARE_UNAVAILABLE", e.message, null)
                    } catch (e: Exception) {
                        result.error(
                            "SHARE_FAILED",
                            "Could not open the source app for sharing.",
                            e.javaClass.simpleName
                        )
                    }
                }
                "clearRecentNotifications" -> {
                    ChatNotificationListenerService.clearEvents()
                    result.success(true)
                }
                "getHomeConfiguration" -> {
                    result.success(
                        mapOf(
                            "sourceMode" to HomePreferences.sourceMode(this),
                            "selectedPackages" to HomePreferences.selectedPackages(this).sorted(),
                            "serviceEnabled" to HomePreferences.isServiceEnabled(this),
                            "notificationAccessGranted" to isNotificationAccessGranted(),
                            "listenerConnected" to
                                ChatNotificationListenerService.isListenerConnected,
                            "captureDiagnosticSchema" to
                                ChatNotificationListenerService.CAPTURE_DIAGNOSTIC_SCHEMA,
                            "captureDiagnostics" to
                                ChatNotificationListenerService.captureDiagnostics.values
                                    .sortedByDescending { it.observedAt }
                                    .take(20)
                                    .map { diagnostic ->
                                        mapOf(
                                            "packageName" to diagnostic.packageName,
                                            "stageCode" to diagnostic.stageCode,
                                            "reasonCode" to diagnostic.reasonCode,
                                            "actionCount" to diagnostic.actionCount,
                                            "remoteInputActionCount" to
                                                diagnostic.remoteInputActionCount,
                                            "freeFormRemoteInputActionCount" to
                                                diagnostic.freeFormRemoteInputActionCount,
                                            "sessionStored" to diagnostic.sessionStored,
                                            "observedAt" to diagnostic.observedAt
                                        )
                                    }
                        )
                    )
                }
                "getSettingsConfiguration" -> {
                    result.success(settingsConfiguration())
                }
                "setSettingsConfiguration" -> {
                    try {
                        val key = call.argument<String>("key")
                            ?: error("Missing setting key")
                        when (key) {
                            "theme" -> HomePreferences.setTheme(
                                this,
                                call.argument<String>("value")
                                    ?: error("Missing theme")
                            )
                            "showUnreadCount" -> HomePreferences.setShowUnreadCount(
                                this,
                                call.argument<Boolean>("value")
                                    ?: error("Missing boolean value")
                            )
                            "maxVisibleBubbles" -> HomePreferences.setMaxVisibleBubbles(
                                this,
                                call.argument<Int>("value")
                                    ?: error("Missing integer value")
                            )
                            "bubbleSize" -> HomePreferences.setBubbleSize(
                                this,
                                call.argument<String>("value")
                                    ?: error("Missing bubble size")
                            )
                            "snapToEdges" -> HomePreferences.setSnapToEdges(
                                this,
                                call.argument<Boolean>("value")
                                    ?: error("Missing boolean value")
                            )
                            "vibrationFeedback" -> HomePreferences.setVibrationFeedback(
                                this,
                                call.argument<Boolean>("value")
                                    ?: error("Missing boolean value")
                            )
                            else -> error("Unknown setting")
                        }
                        FloatingBubbleService.onSettingsChanged()
                        result.success(settingsConfiguration())
                    } catch (e: IllegalArgumentException) {
                        result.error("INVALID_SETTING", e.message, null)
                    } catch (e: IllegalStateException) {
                        result.error("INVALID_SETTING", e.message, null)
                    }
                }
                "setNotificationSourceMode" -> {
                    try {
                        val mode = call.argument<String>("mode")
                            ?: error("Missing notification source mode")
                        HomePreferences.setSourceMode(this, mode)
                        result.success(true)
                    } catch (e: IllegalArgumentException) {
                        result.error("INVALID_MODE", e.message, null)
                    }
                }
                "setSelectedPackages" -> {
                    val packageNames = call.argument<List<String>>("packageNames") ?: emptyList()
                    HomePreferences.setSelectedPackages(this, packageNames)
                    result.success(true)
                }
                "getInstalledApps" -> {
                    try {
                        result.success(loadLaunchableApps())
                    } catch (e: Exception) {
                        result.error("APP_LIST_FAILED", "Could not load installed applications", e.javaClass.simpleName)
                    }
                }
                "exportHistory" -> {
                    if (pendingFileResult != null) {
                        result.error("BUSY", "Another history file operation is active", null)
                    } else {
                        pendingFileResult = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                            putExtra(Intent.EXTRA_TITLE, "floating-chat-backup.json")
                        }
                        startActivityForResult(intent, REQUEST_EXPORT_HISTORY)
                    }
                }
                "importHistory" -> {
                    if (pendingFileResult != null) {
                        result.error("BUSY", "Another history file operation is active", null)
                    } else {
                        pendingFileResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                        }
                        startActivityForResult(intent, REQUEST_IMPORT_HISTORY)
                    }
                }
                "clearHistory" -> {
                    try {
                        ChatHistoryStore.get(this).clearAll()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CLEAR_FAILED", "Could not clear local history", e.javaClass.simpleName)
                    }
                }
                "startBubble" -> {
                    if (Settings.canDrawOverlays(this)) {
                        val serviceIntent = Intent(this, FloatingBubbleService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        HomePreferences.setServiceEnabled(this, true)
                        result.success(true)
                    } else {
                        result.error("PERMISSION_DENIED", "Overlay permission is not granted", null)
                    }
                }
                "stopBubble" -> {
                    val serviceIntent = Intent(this, FloatingBubbleService::class.java)
                    stopService(serviceIntent)
                    HomePreferences.setServiceEnabled(this, false)
                    result.success(true)
                }
                "isBubbleRunning" -> {
                    result.success(FloatingBubbleService.isRunning)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun isNotificationAccessGranted(): Boolean {
        val pkg = packageName
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        if (!flat.isNullOrEmpty()) {
            val names = flat.split(":")
            for (name in names) {
                val cn = ComponentName.unflattenFromString(name)
                if (cn != null && cn.packageName == pkg) {
                    return true
                }
            }
        }
        return NotificationManagerCompat.getEnabledListenerPackages(this).contains(pkg)
    }

    private fun settingsConfiguration(): Map<String, Any> = mapOf(
        "theme" to HomePreferences.theme(this),
        "showUnreadCount" to HomePreferences.showUnreadCount(this),
        "maxVisibleBubbles" to HomePreferences.maxVisibleBubbles(this),
        "bubbleSize" to HomePreferences.bubbleSize(this),
        "snapToEdges" to HomePreferences.snapToEdges(this),
        "vibrationFeedback" to HomePreferences.vibrationFeedback(this)
    )

    private fun loadLaunchableApps(): List<Map<String, Any>> {
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                launcherIntent,
                PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_ALL.toLong())
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(launcherIntent, PackageManager.MATCH_ALL)
        }

        return resolved
            .asSequence()
            .mapNotNull { info ->
                val packageName = info.activityInfo?.packageName ?: return@mapNotNull null
                if (packageName == this.packageName) return@mapNotNull null
                val label = info.loadLabel(packageManager)?.toString()?.trim().orEmpty()
                    .ifBlank { packageName }
                val icon = runCatching { drawableToPng(info.loadIcon(packageManager)) }
                    .getOrElse { ByteArray(0) }
                Triple(packageName, label, icon)
            }
            .distinctBy { it.first }
            .sortedBy { it.second.lowercase() }
            .map { (packageName, label, icon) ->
                mapOf(
                    "packageName" to packageName,
                    "label" to label,
                    "icon" to icon
                )
            }
            .toList()
    }

    private fun loadConversationSummaries(): List<Map<String, Any>> {
        val activeByConversation = ChatNotificationListenerService.activeSessions.values
            .groupBy { session -> session.conversationId }
        val iconCache = mutableMapOf<String, ByteArray>()

        return ChatHistoryStore.get(this).conversationSummaries().map { conversation ->
            val activeSessions = activeByConversation[conversation.id].orEmpty()
            val newestActive = activeSessions.maxByOrNull { it.timestamp }
            val avatar = newestActive?.avatar?.let { bitmap ->
                runCatching { bitmapToPng(bitmap) }.getOrElse { ByteArray(0) }
            } ?: ByteArray(0)
            val appIcon = iconCache.getOrPut(conversation.packageName) {
                runCatching {
                    drawableToPng(packageManager.getApplicationIcon(conversation.packageName))
                }.getOrElse { ByteArray(0) }
            }

            mapOf(
                "id" to conversation.id,
                "appName" to conversation.appName,
                "packageName" to conversation.packageName,
                "title" to conversation.title,
                "latestText" to conversation.latestText,
                "latestTimestamp" to conversation.latestTimestamp,
                "avatar" to avatar,
                "appIcon" to appIcon,
                "unreadCount" to activeSessions.size
            )
        }
    }

    private fun activeSessionsForConversation(
        conversationId: String
    ): List<ChatNotificationListenerService.NotificationSession> =
        ChatNotificationListenerService.activeSessions.values.filter { session ->
            session.conversationId == conversationId
        }

    private fun loadConversationDetails(conversationId: String): Map<String, Any> {
        val messages = ChatHistoryStore.get(this).recentMessages(conversationId, limit = 300)
            .map { message ->
                mapOf<String, Any?>(
                    "text" to message.text,
                    "sender" to message.sender,
                    "timestamp" to message.timestamp,
                    "direction" to message.direction,
                    "replyStatus" to message.replyStatus
                )
            }
        return mapOf("messages" to messages) + replyCapability(conversationId)
    }

    private fun replyCapability(conversationId: String): Map<String, Any> {
        val allSessions = ChatNotificationListenerService.activeSessions.values.toList()
        val activeNotificationSessions = allSessions.filter { it.notificationActive }
        val sessions = allSessions.filter { it.conversationId == conversationId }
        val matchedActiveNotifications = sessions.count { it.notificationActive }
        val retainedReplySessions = sessions.count { !it.notificationActive }
        val notificationAccess = isNotificationAccessGranted()
        val listenerConnected = ChatNotificationListenerService.isListenerConnected
        val storedPackage = ChatHistoryStore.get(this)
            .packageNameForConversation(conversationId)
        val sourcePackageSessions = storedPackage?.let { packageName ->
            allSessions.filter { it.packageName == packageName }
        }.orEmpty()
        val captureDiagnostic = storedPackage?.let { packageName ->
            ChatNotificationListenerService.captureDiagnostics[packageName]
        }
        val hasReplyAction = sessions.any { it.replyAction != null }
        val hasRemoteInput = sessions.any { it.replyRemoteInput != null }
        val canReply = notificationAccess &&
            listenerConnected &&
            hasReplyAction &&
            hasRemoteInput
        val canLaunchSourceApp = storedPackage?.let {
            packageManager.getLaunchIntentForPackage(it) != null
        } == true
        val lastSendAttempt = ChatNotificationListenerService
            .lastReplyAttemptCodes[conversationId] ?: "NOT_ATTEMPTED"
        val stateCode = when {
            !notificationAccess -> "NOTIFICATION_ACCESS_DISABLED"
            !listenerConnected -> "LISTENER_DISCONNECTED"
            storedPackage == null -> "CONVERSATION_METADATA_MISSING"
            sourcePackageSessions.isEmpty() ->
                NotificationCaptureState.noSourceSessionState(
                    captureDiagnostic?.stageCode,
                    captureDiagnostic?.reasonCode
                )
            sessions.isEmpty() -> "CONVERSATION_ID_MISMATCH"
            !hasReplyAction -> "REPLY_ACTION_NOT_DISCOVERED"
            !hasRemoteInput -> "REMOTE_INPUT_NOT_DISCOVERED"
            matchedActiveNotifications > 0 -> "READY_ACTIVE_NOTIFICATION"
            else -> "READY_RETAINED_ACTION"
        }
        val pendingIntentState = when {
            lastSendAttempt == "PENDING_INTENT_CANCELED" -> "CANCELED"
            canReply && matchedActiveNotifications > 0 -> "ACTIVE_UNVERIFIED"
            canReply -> "RETAINED_UNVERIFIED"
            else -> "NOT_AVAILABLE"
        }
        Log.i(
            TAG,
            "capability code=$stateCode conversation=${ChatNotificationListenerService.safeFingerprint(conversationId)} captured=${allSessions.size} activeNotifications=${activeNotificationSessions.size} sourcePackage=${sourcePackageSessions.size} matched=${sessions.size} retained=$retainedReplySessions replyAction=$hasReplyAction remoteInput=$hasRemoteInput pendingIntent=$pendingIntentState lastSend=$lastSendAttempt captureStage=${captureDiagnostic?.stageCode ?: "NOT_OBSERVED"} captureReason=${captureDiagnostic?.reasonCode ?: "NO_SOURCE_EVENT"} captureActions=${captureDiagnostic?.actionCount ?: -1} captureRemoteInputs=${captureDiagnostic?.remoteInputActionCount ?: -1} captureFreeForm=${captureDiagnostic?.freeFormRemoteInputActionCount ?: -1}"
        )
        return mapOf(
            "canReply" to canReply,
            "stateCode" to stateCode,
            "notificationAccessGranted" to notificationAccess,
            "listenerConnected" to listenerConnected,
            "capturedSessionCount" to allSessions.size,
            "activeNotificationCount" to activeNotificationSessions.size,
            "sourcePackageSessionCount" to sourcePackageSessions.size,
            "matchedActiveSessions" to sessions.size,
            "matchedActiveNotificationCount" to matchedActiveNotifications,
            "retainedReplySessionCount" to retainedReplySessions,
            "matchingConversationFound" to sessions.isNotEmpty(),
            "replyActionDiscovered" to hasReplyAction,
            "remoteInputDiscovered" to hasRemoteInput,
            "pendingIntentState" to pendingIntentState,
            "lastSendAttempt" to lastSendAttempt,
            "captureDiagnosticSchema" to
                ChatNotificationListenerService.CAPTURE_DIAGNOSTIC_SCHEMA,
            "captureStageCode" to (captureDiagnostic?.stageCode ?: "NOT_OBSERVED"),
            "captureReasonCode" to (captureDiagnostic?.reasonCode ?: "NO_SOURCE_EVENT"),
            "capturePackageName" to (captureDiagnostic?.packageName ?: storedPackage.orEmpty()),
            "captureActionCount" to (captureDiagnostic?.actionCount ?: -1),
            "captureRemoteInputActionCount" to
                (captureDiagnostic?.remoteInputActionCount ?: -1),
            "captureFreeFormActionCount" to
                (captureDiagnostic?.freeFormRemoteInputActionCount ?: -1),
            "captureSessionStored" to (captureDiagnostic?.sessionStored ?: false),
            "captureObservedAt" to (captureDiagnostic?.observedAt ?: 0L),
            "canOpenConversation" to (
                sessions.any { it.contentIntent != null } || canLaunchSourceApp
            ),
            "replyUnavailableReason" to when {
                canReply -> ""
                !notificationAccess ->
                    "Notification access is disabled, so Floating Chat cannot receive reply actions."
                !listenerConnected ->
                    "Notification access is enabled, but the Android notification listener is disconnected."
                storedPackage == null ->
                    "This stored conversation is missing its source-app metadata."
                sourcePackageSessions.isEmpty() && captureDiagnostic == null ->
                    "The listener is connected, but no notification callback from this source app has been observed in this process."
                sourcePackageSessions.isEmpty() ->
                    captureReasonDescription(captureDiagnostic?.reasonCode ?: "NO_SOURCE_EVENT")
                sessions.isEmpty() ->
                    "A reply session from the source app exists, but its conversation identifier does not match this stored conversation."
                !hasReplyAction ->
                    "The matching notification has no Android reply action."
                !hasRemoteInput ->
                    "The matching notification reply action has no free-form RemoteInput."
                else ->
                    "This ${sessions.maxByOrNull { it.timestamp }?.appName ?: "app"} notification does not provide a free-form Android quick-reply action."
            }
        )
    }

    private fun captureReasonDescription(reasonCode: String): String = when (reasonCode) {
        "NOT_SELECTED_IN_CUSTOM_MODE" ->
            "The source app notification was filtered because the app is not selected in Custom Apps mode."
        "UNSUPPORTED_IN_ALL_APPS_MODE" ->
            "The source package is not in the supported messaging-app list for Listen to all apps mode."
        "ONGOING_NOTIFICATION" ->
            "The source notification was filtered because Android marked it as ongoing."
        "GROUP_SUMMARY" ->
            "The source notification was a group summary rather than a replyable conversation notification."
        "NOTIFICATION_OBJECT_MISSING", "EXTRAS_MISSING" ->
            "Android delivered the source callback without the notification data required for reply capture."
        "NO_CONVERSATION_CONTENT_AFTER_MESSAGING_STYLE" ->
            "The source notification contained no usable conversation title or message after MessagingStyle parsing."
        "NO_NOTIFICATION_ACTIONS", "SESSION_STORED_WITHOUT_ACTIONS" ->
            "The source notification was captured, but it contained no Android actions."
        "NO_REMOTE_INPUT_ACTION", "SESSION_STORED_WITHOUT_REMOTE_INPUT" ->
            "The source notification actions contained no Android RemoteInput."
        "NO_FREE_FORM_REMOTE_INPUT", "SESSION_STORED_WITHOUT_FREE_FORM_REMOTE_INPUT",
        "NOT_REPLY_CAPABLE" ->
            "The source notification contained no free-form Android RemoteInput suitable for a text reply."
        "WHATSAPP_SYNC_PLACEHOLDER" ->
            "The latest WhatsApp callback was a sync placeholder, not a conversation notification."
        else ->
            "The source notification did not produce an available reply session ($reasonCode)."
    }

    private fun copyAttachmentToCache(source: Uri): Map<String, Any> {
        val resolver = contentResolver
        val mimeType = resolver.getType(source) ?: "application/octet-stream"
        val displayName = queryDisplayName(source)
            .ifBlank { "attachment_${System.currentTimeMillis()}" }
        val safeName = displayName.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val directory = File(cacheDir, "composer_attachments").apply { mkdirs() }
        val destination = File(directory, "${System.currentTimeMillis()}_$safeName")
        var copied = 0L
        resolver.openInputStream(source)?.use { input ->
            FileOutputStream(destination).use { output ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    copied += count
                    if (copied > MAX_ATTACHMENT_BYTES) {
                        destination.delete()
                        error("Attachments are limited to 25 MB.")
                    }
                    output.write(buffer, 0, count)
                }
            }
        } ?: error("Could not read the selected attachment.")

        val uri = managedUriFor(destination)
        managedComposerFiles[uri.toString()] = destination
        return attachmentResult(
            file = destination,
            uri = uri,
            displayName = displayName,
            mimeType = mimeType,
            kind = if (mimeType.startsWith("image/")) "image" else "file",
            durationMs = 0L
        )
    }

    private fun queryDisplayName(uri: Uri): String {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index).orEmpty()
            }
        }
        return uri.lastPathSegment.orEmpty()
    }

    private fun attachmentResult(
        file: File,
        uri: Uri,
        displayName: String,
        mimeType: String,
        kind: String,
        durationMs: Long
    ): Map<String, Any> = mapOf(
        "uri" to uri.toString(),
        "name" to displayName,
        "mimeType" to mimeType,
        "kind" to kind,
        "sizeBytes" to file.length(),
        "durationMs" to durationMs,
        "previewBytes" to if (mimeType.startsWith("image/")) {
            imagePreviewBytes(file)
        } else {
            ByteArray(0)
        }
    )

    private fun imagePreviewBytes(file: File): ByteArray {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        var sampleSize = 1
        while (
            bounds.outWidth / sampleSize > 480 ||
            bounds.outHeight / sampleSize > 480
        ) {
            sampleSize *= 2
        }
        val bitmap = BitmapFactory.decodeFile(
            file.absolutePath,
            BitmapFactory.Options().apply { inSampleSize = sampleSize }
        ) ?: return ByteArray(0)
        return try {
            ByteArrayOutputStream().use { output ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 82, output)
                output.toByteArray()
            }
        } finally {
            bitmap.recycle()
        }
    }

    private fun startVoiceRecording(result: MethodChannel.Result) {
        try {
            val directory = File(cacheDir, "voice_replies").apply { mkdirs() }
            val file = File(directory, "voice_${System.currentTimeMillis()}.m4a")
            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            recorder.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(128_000)
                setAudioSamplingRate(44_100)
                setOutputFile(file.absolutePath)
                prepare()
                start()
            }
            mediaRecorder = recorder
            voiceRecordingFile = file
            voiceRecordingStartedAt = System.currentTimeMillis()
            result.success(mapOf("started" to true))
        } catch (e: Exception) {
            releaseRecorder(deleteFile = true)
            result.error(
                "RECORDING_FAILED",
                "Could not start voice recording.",
                e.javaClass.simpleName
            )
        }
    }

    private fun stopVoiceRecording(result: MethodChannel.Result) {
        val recorder = mediaRecorder
        val file = voiceRecordingFile
        if (recorder == null || file == null) {
            result.error("NO_RECORDING", "No voice recording is active.", null)
            return
        }
        val duration = (System.currentTimeMillis() - voiceRecordingStartedAt).coerceAtLeast(0L)
        try {
            recorder.stop()
            recorder.release()
            mediaRecorder = null
            voiceRecordingFile = null
            voiceRecordingStartedAt = 0L
            val uri = managedUriFor(file)
            managedComposerFiles[uri.toString()] = file
            result.success(
                attachmentResult(
                    file = file,
                    uri = uri,
                    displayName = "Voice message.m4a",
                    mimeType = "audio/mp4",
                    kind = "voice",
                    durationMs = duration
                )
            )
        } catch (e: RuntimeException) {
            releaseRecorder(deleteFile = true)
            result.error(
                "RECORDING_TOO_SHORT",
                "The recording was too short. Please try again.",
                e.javaClass.simpleName
            )
        } catch (e: Exception) {
            releaseRecorder(deleteFile = true)
            result.error(
                "RECORDING_FAILED",
                "Could not finish voice recording.",
                e.javaClass.simpleName
            )
        }
    }

    private fun cancelVoiceRecording() {
        try {
            mediaRecorder?.stop()
        } catch (_: Exception) {
            // A short canceled recording may not have enough data to stop cleanly.
        }
        releaseRecorder(deleteFile = true)
    }

    private fun releaseRecorder(deleteFile: Boolean) {
        try {
            mediaRecorder?.reset()
        } catch (_: Exception) {
            // Recorder may already be stopped.
        }
        try {
            mediaRecorder?.release()
        } catch (_: Exception) {
            // Recorder may already be released.
        }
        mediaRecorder = null
        if (deleteFile) voiceRecordingFile?.delete()
        voiceRecordingFile = null
        voiceRecordingStartedAt = 0L
    }

    private fun playVoicePreview(uri: Uri) {
        voicePreviewPlayer?.release()
        voicePreviewPlayer = MediaPlayer().apply {
            setDataSource(this@MainActivity, uri)
            setOnCompletionListener { player ->
                player.release()
                if (voicePreviewPlayer === player) voicePreviewPlayer = null
            }
            prepare()
            start()
        }
    }

    private fun openExternalShare(
        targetPackage: String,
        uri: Uri,
        mimeType: String,
        text: String
    ) {
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            setPackage(targetPackage)
            putExtra(Intent.EXTRA_STREAM, uri)
            if (text.isNotEmpty()) putExtra(Intent.EXTRA_TEXT, text)
            clipData = ClipData.newRawUri("Floating Chat attachment", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (shareIntent.resolveActivity(packageManager) == null) {
            error("The source app cannot accept this attachment through Android sharing.")
        }
        startActivity(shareIntent)
    }

    private fun managedUriFor(file: File): Uri = FileProvider.getUriForFile(
        this,
        "$packageName.fileprovider",
        file
    )

    private fun drawableToPng(drawable: Drawable): ByteArray {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        return ByteArrayOutputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
            output.toByteArray()
        }
    }

    private fun bitmapToPng(bitmap: Bitmap): ByteArray {
        val scaled = if (bitmap.width == 96 && bitmap.height == 96) {
            bitmap
        } else {
            Bitmap.createScaledBitmap(bitmap, 96, 96, true)
        }
        return try {
            ByteArrayOutputStream().use { output ->
                scaled.compress(Bitmap.CompressFormat.PNG, 100, output)
                output.toByteArray()
            }
        } finally {
            if (scaled !== bitmap) scaled.recycle()
        }
    }

    @Deprecated("Uses the platform file picker result API for compatibility with FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_PICK_ATTACHMENT) {
            val callback = pendingAttachmentResult ?: return
            pendingAttachmentResult = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                callback.success(null)
                return
            }
            try {
                callback.success(copyAttachmentToCache(data.data!!))
            } catch (e: Exception) {
                callback.error(
                    "ATTACHMENT_FAILED",
                    e.message ?: "Could not read the selected attachment.",
                    e.javaClass.simpleName
                )
            }
            return
        }
        if (requestCode != REQUEST_EXPORT_HISTORY && requestCode != REQUEST_IMPORT_HISTORY) return
        val callback = pendingFileResult ?: return
        pendingFileResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            callback.success(null)
            return
        }
        try {
            val uri = data.data ?: error("Missing selected file")
            if (requestCode == REQUEST_EXPORT_HISTORY) {
                ChatHistoryStore.get(this).exportTo(this, uri)
                callback.success(mapOf("exported" to true))
            } else {
                val imported = ChatHistoryStore.get(this).importFrom(this, uri)
                FloatingBubbleService.onSettingsChanged()
                callback.success(
                    mapOf(
                        "conversations" to imported.conversations,
                        "messages" to imported.messages
                    )
                )
            }
        } catch (e: Exception) {
            callback.error(
                if (requestCode == REQUEST_EXPORT_HISTORY) "EXPORT_FAILED" else "IMPORT_FAILED",
                e.message ?: "History file operation failed",
                e.javaClass.simpleName
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_RECORD_AUDIO_PERMISSION) return
        val callback = pendingVoicePermissionResult ?: return
        pendingVoicePermissionResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startVoiceRecording(callback)
        } else {
            callback.error(
                "MICROPHONE_DENIED",
                "Microphone permission was not granted.",
                null
            )
        }
    }

    override fun onDestroy() {
        pendingFileResult?.error("ACTIVITY_CLOSED", "The file operation was canceled", null)
        pendingFileResult = null
        pendingAttachmentResult?.error(
            "ACTIVITY_CLOSED",
            "The attachment picker was canceled",
            null
        )
        pendingAttachmentResult = null
        pendingVoicePermissionResult?.error(
            "ACTIVITY_CLOSED",
            "Voice recording was canceled",
            null
        )
        pendingVoicePermissionResult = null
        cancelVoiceRecording()
        voicePreviewPlayer?.release()
        voicePreviewPlayer = null
        super.onDestroy()
        ChatNotificationListenerService.onNotificationCallback = null
        methodChannel = null
    }
}
