package com.example.floating_chat

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.text.Editable
import android.text.TextWatcher
import android.util.Log
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Date
import java.util.LinkedHashMap
import java.util.Locale
import kotlin.math.abs
import kotlin.math.min

class FloatingBubbleService : Service() {

    companion object {
        var isRunning: Boolean = false
            private set
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "floating_bubble_channel"
        private const val TAG = "FloatingBubbleService"

        private var activeInstance: FloatingBubbleService? = null

        fun onSessionReceived(
            session: ChatNotificationListenerService.NotificationSession
        ): String {
            val instance = activeInstance ?: return "SERVICE_NOT_RUNNING"
            instance.handleMultiSession(session)
            return "ENQUEUED"
        }

        fun onNotificationDismissed(id: String) {
            activeInstance?.handleMultiDismissal(id)
        }

        fun onSettingsChanged() {
            activeInstance?.mainHandler?.post {
                activeInstance?.refreshBubbleSettings()
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayLayout: LinearLayout? = null
    private var windowLayoutParams: WindowManager.LayoutParams? = null

    // Bubble Views
    private var bubbleFrame: FrameLayout? = null
    private var bubbleAvatarView: ImageView? = null
    private var bubbleInitialsView: TextView? = null
    private var bubbleBadgeView: TextView? = null

    // Panel Views
    private var popupPanel: LinearLayout? = null
    private var panelAvatarView: ImageView? = null
    private var panelInitialsView: TextView? = null
    private var panelTitle: TextView? = null
    private var panelSubtitle: TextView? = null
    private var panelIncomingMessage: TextView? = null
    private var panelOutgoingMessage: TextView? = null
    private var panelOutgoingContainer: LinearLayout? = null
    private var replyInput: EditText? = null
    private var sendButton: Button? = null
    private var replyNotice: TextView? = null
    private var openInAppButton: Button? = null

    private var currentSession: ChatNotificationListenerService.NotificationSession? = null
    private var isNotificationActive: Boolean = true

    private val mainHandler = Handler(Looper.getMainLooper())

    private data class ObservedMessage(
        val text: String,
        val timestamp: Long,
        val direction: String = "incoming",
        val sender: String? = null,
        val replyStatus: String? = null
    )

    private data class ConversationState(
        var session: ChatNotificationListenerService.NotificationSession,
        val messages: MutableList<ObservedMessage> = mutableListOf(),
        val activeNotificationIds: MutableSet<String> = mutableSetOf(),
        var notificationActive: Boolean = true,
        var replyStatus: String? = null,
        var lastUpdated: Long = session.timestamp
    )

    private data class MultiBubble(
        val view: FrameLayout,
        val avatar: ImageView,
        val initials: TextView,
        val badge: TextView,
        val params: WindowManager.LayoutParams
    )

    private val conversationStates = LinkedHashMap<String, ConversationState>()
    private val multiBubbles = LinkedHashMap<String, MultiBubble>()
    private val notificationToConversation = mutableMapOf<String, String>()
    private var bubbleGroup: LinearLayout? = null
    private var bubbleGroupParams: WindowManager.LayoutParams? = null
    private var groupExpanded = false
    private var groupSnappedRight = true
    private var primaryConversationId: String? = null
    private var groupYBeforeCard: Int? = null
    private var overflowPanel: LinearLayout? = null
    private var expandedConversationId: String? = null
    private var floatingCard: LinearLayout? = null
    private var cardTitleView: TextView? = null
    private var cardSubtitleView: TextView? = null
    private var cardMessagesView: LinearLayout? = null
    private var cardScrollView: ScrollView? = null
    private var cardStatusView: TextView? = null
    private var cardInputView: EditText? = null
    private var cardSendView: Button? = null
    private var removeTarget: LinearLayout? = null
    private var removeTargetParams: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        activeInstance = this
        Log.i(
            TAG,
            "bubble stage=SERVICE_CREATED overlayPermission=${Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)}"
        )
        startInForeground()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createRemoveTarget()

        val activeSessions = ChatNotificationListenerService.activeSessions.values.sortedBy { it.timestamp }
        if (activeSessions.isNotEmpty()) {
            activeSessions.forEach { upsertMultiConversation(it) }
        } else {
            ChatNotificationListenerService.latestSession?.let { upsertMultiConversation(it) }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (HomePreferences.theme(this) == HomePreferences.THEME_SYSTEM) {
            mainHandler.post { refreshBubbleSettings() }
        }
    }

    private fun startInForeground() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Floating Chat Bubble",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps the floating chat bubble active above other apps"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, pendingIntentFlags)

        val notificationBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val notification = notificationBuilder
            .setContentTitle("Floating Chat Heads")
            .setContentText("Chat head active. Tap to expand.")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createFloatingOverlay() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dpToPx(24)
            y = dpToPx(140)
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }
        windowLayoutParams = params

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        overlayLayout = root

        // --- 1. CIRCULAR CHAT HEAD BUBBLE (Messenger Style) ---
        val bubbleSize = dpToPx(62)
        val frame = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(bubbleSize, bubbleSize)
            elevation = dpToPx(8).toFloat()
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#1E88E5"))
            }
        }
        bubbleFrame = frame

        // Sender Avatar ImageView (clipped circular)
        val avatar = ImageView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            scaleType = ImageView.ScaleType.CENTER_CROP
            visibility = View.GONE
        }
        bubbleAvatarView = avatar

        // Fallback initials TextView
        val initials = TextView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            gravity = Gravity.CENTER
            textSize = 20f
            setTextColor(Color.WHITE)
            paint.isFakeBoldText = true
            text = "💬"
        }
        bubbleInitialsView = initials

        // App Mini Badge (Bottom-Right circle showing app identity)
        val badge = TextView(this).apply {
            val badgeSize = dpToPx(20)
            layoutParams = FrameLayout.LayoutParams(badgeSize, badgeSize).apply {
                gravity = Gravity.BOTTOM or Gravity.END
            }
            gravity = Gravity.CENTER
            textSize = 10f
            setTextColor(Color.WHITE)
            paint.isFakeBoldText = true
            text = "W"
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#25D366"))
                setStroke(dpToPx(1), Color.WHITE)
            }
            visibility = View.GONE
        }
        bubbleBadgeView = badge

        frame.addView(avatar)
        frame.addView(initials)
        frame.addView(badge)

        // --- 2. EXPANDABLE CONVERSATION PANEL ---
        val panel = createConversationPanel()
        popupPanel = panel

        root.addView(frame)
        root.addView(panel)

        // Touch & Drag Handling
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isClick = false

        frame.setOnTouchListener { _, event ->
            val curParams = windowLayoutParams ?: return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = curParams.x
                    initialY = curParams.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isClick = true
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaX = (event.rawX - initialTouchX).toInt()
                    val deltaY = (event.rawY - initialTouchY).toInt()
                    if (Math.hypot(deltaX.toDouble(), deltaY.toDouble()) > dpToPx(6)) {
                        isClick = false
                    }
                    curParams.x = initialX + deltaX
                    curParams.y = initialY + deltaY
                    windowManager?.updateViewLayout(root, curParams)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (isClick) {
                        if (currentSession?.packageName == "com.whatsapp") {
                            openCurrentConversationFromNotification()
                        } else {
                            togglePanel()
                        }
                    } else {
                        // Snap bubble to nearest screen edge
                        val screenWidth = resources.displayMetrics.widthPixels
                        val margin = dpToPx(16)
                        curParams.x = if (curParams.x + (bubbleSize / 2) < screenWidth / 2) {
                            margin
                        } else {
                            screenWidth - bubbleSize - margin
                        }
                        windowManager?.updateViewLayout(root, curParams)
                    }
                    true
                }
                else -> false
            }
        }

        try {
            windowManager?.addView(root, params)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun createConversationPanel(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val padding = dpToPx(14)
            setPadding(padding, padding, padding, padding)

            layoutParams = LinearLayout.LayoutParams(
                dpToPx(285),
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dpToPx(8)
            }

            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadius = dpToPx(18).toFloat()
                setStroke(dpToPx(1), Color.parseColor("#E5E7EB"))
            }
            elevation = dpToPx(12).toFloat()
            visibility = View.GONE

            // Header Row: Avatar, Title, Open in App, Close
            val headerRow = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                )
                gravity = Gravity.CENTER_VERTICAL
            }

            // Panel mini avatar/initials container
            val miniAvatarFrame = FrameLayout(context).apply {
                val size = dpToPx(34)
                layoutParams = LinearLayout.LayoutParams(size, size).apply {
                    rightMargin = dpToPx(10)
                }
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.parseColor("#1E88E5"))
                }
            }

            val pAvatar = ImageView(context).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                scaleType = ImageView.ScaleType.CENTER_CROP
                visibility = View.GONE
            }
            panelAvatarView = pAvatar

            val pInitials = TextView(context).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                gravity = Gravity.CENTER
                textSize = 13f
                setTextColor(Color.WHITE)
                paint.isFakeBoldText = true
                text = "💬"
            }
            panelInitialsView = pInitials

            miniAvatarFrame.addView(pAvatar)
            miniAvatarFrame.addView(pInitials)
            headerRow.addView(miniAvatarFrame)

            // Title & Subtitle column
            val titleCol = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    0,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    1f
                )
            }

            val titleView = TextView(context).apply {
                text = "Floating Chat"
                textSize = 15f
                paint.isFakeBoldText = true
                setTextColor(Color.parseColor("#111827"))
                maxLines = 1
            }
            panelTitle = titleView

            val subtitleView = TextView(context).apply {
                text = "No active message"
                textSize = 11f
                setTextColor(Color.parseColor("#6B7280"))
                maxLines = 1
            }
            panelSubtitle = subtitleView

            titleCol.addView(titleView)
            titleCol.addView(subtitleView)
            headerRow.addView(titleCol)

            // "Open in App" Button
            val openBtn = Button(context).apply {
                text = "↗"
                textSize = 16f
                setTextColor(Color.parseColor("#2563EB"))
                background = null
                val minSize = dpToPx(32)
                layoutParams = LinearLayout.LayoutParams(minSize, minSize)
                setOnClickListener { openOriginalApp() }
            }
            openInAppButton = openBtn
            headerRow.addView(openBtn)

            // Close '✕' Button
            val closeBtn = Button(context).apply {
                text = "✕"
                textSize = 14f
                setTextColor(Color.parseColor("#9CA3AF"))
                background = null
                val minSize = dpToPx(32)
                layoutParams = LinearLayout.LayoutParams(minSize, minSize)
                setOnClickListener { collapsePanel() }
            }
            headerRow.addView(closeBtn)

            addView(headerRow)

            // Divider
            addView(View(context).apply {
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dpToPx(1)
                ).apply {
                    topMargin = dpToPx(10)
                    bottomMargin = dpToPx(10)
                }
                setBackgroundColor(Color.parseColor("#F3F4F6"))
            })

            // Incoming Message Bubble Container
            val incomingCard = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dpToPx(12), dpToPx(10), dpToPx(12), dpToPx(10))
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                )
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#F3F4F6"))
                    cornerRadius = dpToPx(14).toFloat()
                }
            }

            val msgView = TextView(context).apply {
                text = "Waiting for incoming WhatsApp, Telegram, or Messenger message..."
                textSize = 13f
                setTextColor(Color.parseColor("#1F2937"))
                maxLines = 5
            }
            panelIncomingMessage = msgView

            val noticeLabel = TextView(context).apply {
                text = "Notification preview"
                textSize = 10f
                setTextColor(Color.parseColor("#9CA3AF"))
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    topMargin = dpToPx(4)
                }
            }

            incomingCard.addView(msgView)
            incomingCard.addView(noticeLabel)
            addView(incomingCard)

            // Outgoing Message Bubble (Optimistic Sent Preview)
            val outgoingCard = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dpToPx(12), dpToPx(8), dpToPx(12), dpToPx(8))
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    topMargin = dpToPx(8)
                    gravity = Gravity.END
                }
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#2563EB"))
                    cornerRadius = dpToPx(14).toFloat()
                }
                visibility = View.GONE
            }
            panelOutgoingContainer = outgoingCard

            val sentMsgView = TextView(context).apply {
                text = ""
                textSize = 13f
                setTextColor(Color.WHITE)
            }
            panelOutgoingMessage = sentMsgView
            outgoingCard.addView(sentMsgView)
            addView(outgoingCard)

            // Quick Reply Input Section
            val replyBox = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    topMargin = dpToPx(12)
                }
            }

            val edit = EditText(context).apply {
                hint = "Type a reply..."
                textSize = 13f
                setTextColor(Color.parseColor("#111827"))
                setHintTextColor(Color.parseColor("#9CA3AF"))
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#F9FAFB"))
                    cornerRadius = dpToPx(20).toFloat()
                    setStroke(dpToPx(1), Color.parseColor("#D1D5DB"))
                }
                setPadding(dpToPx(12), dpToPx(8), dpToPx(12), dpToPx(8))
                maxLines = 3
                layoutParams = LinearLayout.LayoutParams(
                    0,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    1f
                )
            }
            replyInput = edit

            val sendBtn = Button(context).apply {
                text = "Send"
                textSize = 12f
                paint.isFakeBoldText = true
                setTextColor(Color.WHITE)
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#2563EB"))
                    cornerRadius = dpToPx(18).toFloat()
                }
                layoutParams = LinearLayout.LayoutParams(
                    dpToPx(60),
                    dpToPx(36)
                ).apply {
                    leftMargin = dpToPx(8)
                }
                isEnabled = false
                alpha = 0.5f
                setOnClickListener { triggerSendReply() }
            }
            sendButton = sendBtn

            edit.addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    val hasText = !s.isNullOrBlank()
                    val canReply = currentSession?.replyAction != null && isNotificationActive
                    sendBtn.isEnabled = hasText && canReply
                    sendBtn.alpha = if (hasText && canReply) 1.0f else 0.5f
                }
                override fun afterTextChanged(s: Editable?) {}
            })

            replyBox.addView(edit)
            replyBox.addView(sendBtn)
            addView(replyBox)

            // Helper notice when quick reply is unavailable or expired
            val noticeView = TextView(context).apply {
                text = ""
                textSize = 11f
                setTextColor(Color.parseColor("#9CA3AF"))
                gravity = Gravity.CENTER
                visibility = View.GONE
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    topMargin = dpToPx(6)
                }
            }
            replyNotice = noticeView
            addView(noticeView)
        }
    }

    private fun togglePanel() {
        if (popupPanel?.visibility == View.VISIBLE) {
            collapsePanel()
        } else {
            expandPanel()
        }
    }

    private fun expandPanel() {
        val root = overlayLayout ?: return
        val params = windowLayoutParams ?: return

        popupPanel?.visibility = View.VISIBLE

        // Remove NOT_FOCUSABLE flag so the soft keyboard and EditText work
        params.flags = params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
        windowManager?.updateViewLayout(root, params)

        // Focus reply input if reply is supported
        if (currentSession?.replyAction != null && isNotificationActive) {
            replyInput?.requestFocus()
        }
    }

    private fun collapsePanel() {
        val root = overlayLayout ?: return
        val params = windowLayoutParams ?: return

        // Hide keyboard
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        replyInput?.let { edit ->
            imm?.hideSoftInputFromWindow(edit.windowToken, 0)
            edit.clearFocus()
        }

        popupPanel?.visibility = View.GONE

        // Restore NOT_FOCUSABLE flag so outside touches pass through
        params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        windowManager?.updateViewLayout(root, params)
    }

    private fun handleNewSession(session: ChatNotificationListenerService.NotificationSession) {
        mainHandler.post {
            currentSession = session
            isNotificationActive = true
            applySessionToViews(session, autoExpand = true)
        }
    }

    private fun applySessionToViews(
        session: ChatNotificationListenerService.NotificationSession,
        autoExpand: Boolean = true
    ) {
        val appName = session.appName
        val title = session.title.ifEmpty { appName }
        val message = session.text.ifEmpty { "(No preview content available)" }

        val (appColor, appInitial) = when (appName.lowercase()) {
            "whatsapp", "whatsapp business" -> Pair(Color.parseColor("#25D366"), "W")
            "telegram" -> Pair(Color.parseColor("#229ED9"), "T")
            "slack" -> Pair(Color.parseColor("#611F69"), "S")
            "messenger" -> Pair(Color.parseColor("#0084FF"), "M")
            else -> Pair(Color.parseColor("#1E88E5"), "💬")
        }

        // --- 1. Update Bubble Identity ---
        val initials = getInitials(title)
        if (session.avatar != null) {
            val circularAvatar = getCircularBitmap(session.avatar)
            bubbleAvatarView?.setImageBitmap(circularAvatar)
            bubbleAvatarView?.visibility = View.VISIBLE
            bubbleInitialsView?.visibility = View.GONE

            panelAvatarView?.setImageBitmap(circularAvatar)
            panelAvatarView?.visibility = View.VISIBLE
            panelInitialsView?.visibility = View.GONE
        } else {
            bubbleAvatarView?.visibility = View.GONE
            bubbleInitialsView?.apply {
                text = initials
                visibility = View.VISIBLE
            }

            panelAvatarView?.visibility = View.GONE
            panelInitialsView?.apply {
                text = initials
                visibility = View.VISIBLE
            }
        }

        // Update bubble badge with app initial & color
        bubbleBadgeView?.apply {
            text = appInitial
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(appColor)
                setStroke(dpToPx(1), Color.WHITE)
            }
            visibility = View.VISIBLE
        }

        // --- 2. Update Panel Content ---
        panelTitle?.text = title

        val timeStr = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date(session.timestamp))
        panelSubtitle?.text = "$appName • $timeStr"
        panelIncomingMessage?.text = message

        // Hide old outgoing sent preview for new conversation event
        panelOutgoingContainer?.visibility = View.GONE

        // --- 3. Quick Reply Capability Check ---
        val hasReply = session.replyAction != null && session.replyRemoteInput != null
        if (hasReply) {
            replyInput?.isEnabled = true
            replyNotice?.visibility = View.GONE
            sendButton?.isEnabled = !replyInput?.text.isNullOrBlank()
            sendButton?.alpha = if (sendButton?.isEnabled == true) 1.0f else 0.5f
        } else {
            replyInput?.isEnabled = true
            sendButton?.isEnabled = false
            sendButton?.alpha = 0.5f
            replyNotice?.apply {
                text = "Quick reply not supported for this notification • Use Open in app"
                visibility = View.VISIBLE
            }
        }

        if (autoExpand) {
            expandPanel()
        }
    }

    private fun triggerSendReply() {
        val current = currentSession ?: return
        val text = replyInput?.text?.toString()?.trim() ?: return
        if (text.isEmpty()) return

        val conversationId = ChatHistoryStore.conversationId(
            current.packageName,
            current.title,
            current.id
        )
        val session = activeReplySessionForConversation(conversationId)
        if (session == null) {
            Toast.makeText(
                this,
                "No active quick-reply action. Draft kept; use Open in app.",
                Toast.LENGTH_LONG
            ).show()
            return
        }

        val attempt = ChatNotificationListenerService.sendQuickReply(this, session, text)
        if (attempt.accepted) {
            panelOutgoingMessage?.text = "You: $text · delivery unconfirmed"
            panelOutgoingContainer?.visibility = View.VISIBLE

            try {
                ChatHistoryStore.get(this).recordOutgoing(
                    conversationId,
                    text,
                    System.currentTimeMillis(),
                    "submitted; delivery unconfirmed"
                )
            } catch (_: Exception) {
                // The source app accepted the handoff even if local persistence failed.
            }

            // Clear input & dismiss keyboard
            replyInput?.setText("")
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            replyInput?.let { imm?.hideSoftInputFromWindow(it.windowToken, 0) }

            Toast.makeText(
                this,
                "Reply handed to ${session.appName}; delivery is not confirmed",
                Toast.LENGTH_LONG
            ).show()
        } else {
            Toast.makeText(
                this,
                "Could not send reply (${attempt.code}). Draft kept; tap 'Open in app'.",
                Toast.LENGTH_LONG
            ).show()
        }
    }

    private fun openCurrentConversationFromNotification() {
        val contentIntent = currentSession?.contentIntent
        if (contentIntent == null) {
            Toast.makeText(
                this,
                "Conversation cannot be opened from this notification",
                Toast.LENGTH_SHORT
            ).show()
            return
        }

        try {
            contentIntent.send()
            collapsePanel()
        } catch (e: PendingIntent.CanceledException) {
            Toast.makeText(
                this,
                "Conversation cannot be opened from this notification",
                Toast.LENGTH_SHORT
            ).show()
        } catch (e: Exception) {
            Toast.makeText(
                this,
                "Could not open this conversation",
                Toast.LENGTH_SHORT
            ).show()
        }
    }

    private fun openOriginalApp() {
        val session = currentSession
        if (session?.contentIntent != null) {
            try {
                session.contentIntent.send()
                collapsePanel()
                return
            } catch (e: Exception) {
                // Fallback to launcher intent
            }
        }

        if (session != null) {
            val launchIntent = packageManager.getLaunchIntentForPackage(session.packageName)
            if (launchIntent != null) {
                launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(launchIntent)
                collapsePanel()
                return
            }
        }

        Toast.makeText(this, "Could not open messaging app", Toast.LENGTH_SHORT).show()
    }

    private fun handleDismissal(id: String) {
        mainHandler.post {
            if (currentSession?.id == id) {
                isNotificationActive = false
                // Preserve the draft editor even though the notification-backed send action expired.
                replyInput?.isEnabled = true
                sendButton?.isEnabled = false
                sendButton?.alpha = 0.5f
                replyNotice?.apply {
                    text = "Notification cleared from status bar • Use Open in app"
                    visibility = View.VISIBLE
                }
            }
        }
    }

    private fun overlayWindowType(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
    }

    private fun handleMultiSession(session: ChatNotificationListenerService.NotificationSession) {
        val conversationFingerprint =
            ChatNotificationListenerService.safeFingerprint(session.conversationId)
        Log.i(
            TAG,
            "bubble stage=SESSION_RECEIVED pkg=${session.packageName} conversation=$conversationFingerprint"
        )
        mainHandler.post {
            try {
                upsertMultiConversation(session)
                Log.i(
                    TAG,
                    "bubble stage=RENDER_COMPLETE pkg=${session.packageName} conversation=$conversationFingerprint attached=${bubbleGroup?.isAttachedToWindow == true}"
                )
            } catch (e: Exception) {
                Log.e(
                    TAG,
                    "bubble stage=RENDER_FAILED pkg=${session.packageName} conversation=$conversationFingerprint type=${e.javaClass.simpleName}"
                )
            }
        }
    }

    private fun upsertMultiConversation(session: ChatNotificationListenerService.NotificationSession) {
        overlayLayout?.visibility = View.GONE
        val conversationId = conversationIdFor(session)
        notificationToConversation[session.id] = conversationId
        val state = conversationStates[conversationId]
        if (state == null) {
            val created = ConversationState(session).apply {
                activeNotificationIds.add(session.id)
                try {
                    messages.addAll(
                        ChatHistoryStore.get(this@FloatingBubbleService)
                            .recentMessages(conversationId)
                            .map {
                                ObservedMessage(
                                    it.text,
                                    it.timestamp,
                                    it.direction,
                                    it.sender,
                                    it.replyStatus
                                )
                            }
                    )
                } catch (_: Exception) {
                    // A database problem must not prevent the live overlay from working.
                }
            }
            appendObservedMessage(created, session)
            conversationStates[conversationId] = created
        } else {
            state.session = session
            state.activeNotificationIds.add(session.id)
            state.notificationActive = true
            state.replyStatus = null
            state.lastUpdated = session.timestamp
            appendObservedMessage(state, session)
        }

        primaryConversationId = conversationId
        renderBubbleGroup()

        if (expandedConversationId == conversationId) {
            renderFloatingCard()
        }
    }

    private fun conversationIdFor(
        session: ChatNotificationListenerService.NotificationSession
    ): String {
        return session.conversationId
    }

    private fun appendObservedMessage(
        state: ConversationState,
        session: ChatNotificationListenerService.NotificationSession
    ) {
        val text = session.text.trim()
        if (text.isEmpty()) return
        if (session.direction == "outgoing") {
            val matchingIndex = state.messages.indexOfLast { message ->
                message.direction == "outgoing" &&
                    message.text == text &&
                    abs(message.timestamp - session.timestamp) <= 120_000L
            }
            if (matchingIndex >= 0) {
                val existing = state.messages[matchingIndex]
                state.messages[matchingIndex] = existing.copy(
                    replyStatus = "sent; observed in source notification"
                )
                return
            }
        }
        val previous = state.messages.lastOrNull()
        if (
            previous == null ||
            previous.text != text ||
            previous.direction != session.direction ||
            abs(previous.timestamp - session.timestamp) > 1_000L
        ) {
            state.messages.add(
                ObservedMessage(
                    text = text,
                    timestamp = session.timestamp,
                    direction = session.direction,
                    sender = if (session.direction == "incoming") {
                        session.senderName ?: session.title.ifBlank { null }
                    } else {
                        null
                    },
                    replyStatus = if (session.direction == "outgoing") {
                        "sent; observed in source notification"
                    } else {
                        null
                    }
                )
            )
            while (state.messages.size > 30) {
                state.messages.removeAt(0)
            }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun configuredBubbleSizePx(): Int = dpToPx(
        when (HomePreferences.bubbleSize(this)) {
            HomePreferences.BUBBLE_SIZE_SMALL -> 56
            HomePreferences.BUBBLE_SIZE_LARGE -> 72
            else -> 64
        }
    )

    private fun performBubbleHaptic(view: View, feedbackConstant: Int) {
        if (HomePreferences.vibrationFeedback(this)) {
            view.performHapticFeedback(feedbackConstant)
        }
    }

    private fun refreshBubbleSettings() {
        val openConversationId = expandedConversationId
        if (openConversationId != null) closeFloatingCard()
        if (conversationStates.isEmpty()) return
        renderBubbleGroup()
        settleBubbleGroup()
        if (openConversationId != null && conversationStates.containsKey(openConversationId)) {
            openFloatingCard(openConversationId)
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun renderBubbleGroup() {
        val ordered = conversationStates.entries
            .sortedByDescending { it.value.lastUpdated }
        if (ordered.isEmpty()) {
            bubbleGroup?.let { safeRemoveOverlay(it) }
            bubbleGroup = null
            bubbleGroupParams = null
            closeOverflowPanel()
            overlayLayout?.visibility = View.VISIBLE
            return
        }

        val primaryId = primaryConversationId
            ?.takeIf { conversationStates.containsKey(it) }
            ?: ordered.first().key
        primaryConversationId = primaryId

        val bubbleSize = configuredBubbleSizePx()
        val gap = dpToPx(8)
        val root = bubbleGroup ?: LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            clipChildren = false
            clipToPadding = false
            setOnTouchListener { _, event ->
                if (event.actionMasked == MotionEvent.ACTION_OUTSIDE) {
                    collapseBubbleGroup()
                    true
                } else {
                    false
                }
            }
        }.also { bubbleGroup = it }
        root.removeAllViews()

        val maxVisibleBubbles = HomePreferences.maxVisibleBubbles(this)
        val visibleIds = if (groupExpanded) {
            ordered.take(maxVisibleBubbles).map { it.key }
        } else {
            listOf(primaryId)
        }
        visibleIds.forEachIndexed { index, id ->
            val state = conversationStates[id] ?: return@forEachIndexed
            root.addView(
                createGroupedConversationBubble(
                    id,
                    state,
                    if (!groupExpanded) ordered.size - 1 else 0,
                    bubbleSize
                ),
                LinearLayout.LayoutParams(bubbleSize, bubbleSize).apply {
                    if (index > 0) leftMargin = gap
                }
            )
        }

        if (groupExpanded && ordered.size > maxVisibleBubbles) {
            root.addView(
                createOverflowBubble(ordered.size - maxVisibleBubbles, bubbleSize),
                LinearLayout.LayoutParams(bubbleSize, bubbleSize).apply {
                    leftMargin = gap
                }
            )
        }

        val itemCount = visibleIds.size +
            if (groupExpanded && ordered.size > maxVisibleBubbles) 1 else 0
        val groupWidth = itemCount * bubbleSize + (itemCount - 1).coerceAtLeast(0) * gap
        val isNewGroup = bubbleGroupParams == null
        val params = bubbleGroupParams ?: WindowManager.LayoutParams(
            groupWidth,
            bubbleSize,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            y = dpToPx(120)
        }.also { bubbleGroupParams = it }
        params.width = groupWidth
        params.height = bubbleSize
        val maxX = (resources.displayMetrics.widthPixels - groupWidth).coerceAtLeast(0)
        params.x = if (HomePreferences.snapToEdges(this) || isNewGroup) {
            if (groupSnappedRight) {
                resources.displayMetrics.widthPixels - groupWidth - dpToPx(16)
            } else {
                dpToPx(16)
            }
        } else {
            params.x.coerceIn(0, maxX)
        }
        params.x = params.x.coerceAtLeast(0)

        try {
            if (root.isAttachedToWindow) {
                windowManager?.updateViewLayout(root, params)
            } else {
                windowManager?.addView(root, params)
            }
        } catch (e: Exception) {
            bubbleGroup = null
            bubbleGroupParams = null
            Log.e(TAG, "bubble stage=WINDOW_ADD_FAILED type=${e.javaClass.simpleName}")
            Toast.makeText(this, "Could not show conversation bubbles", Toast.LENGTH_SHORT).show()
        }
    }

    private fun createGroupedConversationBubble(
        id: String,
        state: ConversationState,
        additionalCount: Int,
        bubbleSize: Int
    ): FrameLayout {
        val session = state.session
        val title = session.title.ifEmpty { session.appName }
        return FrameLayout(this).apply {
            elevation = dpToPx(10).toFloat()
            background = ovalDrawable(Color.parseColor("#1E88E5"))
            contentDescription = if (groupExpanded) {
                "Open $title from ${session.appName}"
            } else {
                "Expand conversations. $title selected"
            }

            if (session.avatar != null) {
                addView(ImageView(context).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                    scaleType = ImageView.ScaleType.CENTER_CROP
                    setImageBitmap(getCircularBitmap(session.avatar))
                })
            } else {
                addView(TextView(context).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                    gravity = Gravity.CENTER
                    text = getInitials(title)
                    textSize = 19f
                    setTextColor(Color.WHITE)
                    paint.isFakeBoldText = true
                })
            }

            val (badgeColor, badgeInitial) = appBadgeStyle(session.appName)
            addView(TextView(context).apply {
                val badgeSize = dpToPx(21)
                layoutParams = FrameLayout.LayoutParams(badgeSize, badgeSize).apply {
                    gravity = Gravity.BOTTOM or Gravity.END
                }
                gravity = Gravity.CENTER
                text = badgeInitial
                textSize = 10f
                setTextColor(Color.WHITE)
                paint.isFakeBoldText = true
                background = ovalDrawable(badgeColor, Color.WHITE)
            })

            if (additionalCount > 0 && HomePreferences.showUnreadCount(context)) {
                addView(TextView(context).apply {
                    layoutParams = FrameLayout.LayoutParams(dpToPx(30), dpToPx(22)).apply {
                        gravity = Gravity.TOP or Gravity.END
                        topMargin = -dpToPx(4)
                        rightMargin = -dpToPx(5)
                    }
                    gravity = Gravity.CENTER
                    text = "+$additionalCount"
                    textSize = 9.5f
                    setTextColor(Color.WHITE)
                    paint.isFakeBoldText = true
                    background = roundedDrawable(
                        Color.parseColor("#DC2626"),
                        dpToPx(11).toFloat(),
                        Color.WHITE
                    )
                })
            }
            installGroupedBubbleTouch(id, this, bubbleSize)
        }
    }

    private fun createOverflowBubble(count: Int, bubbleSize: Int): FrameLayout {
        return FrameLayout(this).apply {
            background = ovalDrawable(Color.parseColor("#374151"), Color.WHITE)
            elevation = dpToPx(10).toFloat()
            contentDescription = "Open $count more conversations"
            addView(TextView(context).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                gravity = Gravity.CENTER
                text = "+$count"
                textSize = 16f
                setTextColor(Color.WHITE)
                paint.isFakeBoldText = true
            })
            setOnClickListener { openOverflowPanel() }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun installGroupedBubbleTouch(id: String, bubble: View, bubbleSize: Int) {
        var initialX = 0
        var initialY = 0
        var touchX = 0f
        var touchY = 0f
        var dragging = false

        bubble.setOnTouchListener { _, event ->
            val params = bubbleGroupParams ?: return@setOnTouchListener false
            val group = bubbleGroup ?: return@setOnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    dragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaX = (event.rawX - touchX).toInt()
                    val deltaY = (event.rawY - touchY).toInt()
                    if (!dragging && Math.hypot(deltaX.toDouble(), deltaY.toDouble()) > dpToPx(8)) {
                        dragging = true
                        performBubbleHaptic(bubble, HapticFeedbackConstants.LONG_PRESS)
                        showRemoveTarget()
                    }
                    if (dragging) {
                        val screenWidth = resources.displayMetrics.widthPixels
                        val screenHeight = resources.displayMetrics.heightPixels
                        params.x = (initialX + deltaX).coerceIn(
                            0,
                            (screenWidth - params.width).coerceAtLeast(0)
                        )
                        params.y = (initialY + deltaY).coerceIn(
                            0,
                            (screenHeight - params.height).coerceAtLeast(0)
                        )
                        windowManager?.updateViewLayout(group, params)
                        highlightRemoveTarget(isPointOverRemoveTarget(event.rawX, event.rawY))
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (dragging) {
                        if (isPointOverRemoveTarget(event.rawX, event.rawY)) {
                            dismissGroupedConversation(id)
                        } else {
                            settleBubbleGroup()
                        }
                        hideRemoveTarget()
                    } else if (groupExpanded) {
                        performBubbleHaptic(bubble, HapticFeedbackConstants.VIRTUAL_KEY)
                        openFloatingCard(id)
                    } else {
                        performBubbleHaptic(bubble, HapticFeedbackConstants.VIRTUAL_KEY)
                        groupExpanded = true
                        renderBubbleGroup()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    if (dragging) settleBubbleGroup()
                    hideRemoveTarget()
                    true
                }
                else -> false
            }
        }
    }

    private fun snapBubbleGroup() {
        val group = bubbleGroup ?: return
        val params = bubbleGroupParams ?: return
        val screenWidth = resources.displayMetrics.widthPixels
        groupSnappedRight = params.x + params.width / 2 >= screenWidth / 2
        params.x = if (groupSnappedRight) {
            screenWidth - params.width - dpToPx(16)
        } else {
            dpToPx(16)
        }.coerceAtLeast(0)
        params.y = params.y.coerceIn(
            dpToPx(36),
            (resources.displayMetrics.heightPixels - params.height - dpToPx(36))
                .coerceAtLeast(dpToPx(36))
        )
        windowManager?.updateViewLayout(group, params)
    }

    private fun settleBubbleGroup() {
        if (HomePreferences.snapToEdges(this)) {
            snapBubbleGroup()
            return
        }
        val group = bubbleGroup ?: return
        val params = bubbleGroupParams ?: return
        params.x = params.x.coerceIn(
            0,
            (resources.displayMetrics.widthPixels - params.width).coerceAtLeast(0)
        )
        params.y = params.y.coerceIn(
            0,
            (resources.displayMetrics.heightPixels - params.height).coerceAtLeast(0)
        )
        windowManager?.updateViewLayout(group, params)
    }

    private fun collapseBubbleGroup() {
        if (!groupExpanded) return
        groupExpanded = false
        closeOverflowPanel()
        renderBubbleGroup()
    }

    private fun isPointOverRemoveTarget(rawX: Float, rawY: Float): Boolean {
        if (removeTarget == null) return false
        val targetSize = dpToPx(92)
        val centerX = resources.displayMetrics.widthPixels / 2f
        val centerY = resources.displayMetrics.heightPixels -
            (removeTargetParams?.y ?: dpToPx(24)) - targetSize / 2f
        return Math.hypot(
            (rawX - centerX).toDouble(),
            (rawY - centerY).toDouble()
        ) <= targetSize * 0.72
    }

    private fun dismissGroupedConversation(id: String) {
        if (expandedConversationId == id) closeFloatingCard()
        conversationStates.remove(id)
        notificationToConversation.entries.removeAll { it.value == id }
        if (primaryConversationId == id) {
            primaryConversationId = conversationStates.entries
                .maxByOrNull { it.value.lastUpdated }
                ?.key
        }
        if (conversationStates.size <= 1) groupExpanded = false
        closeOverflowPanel()
        renderBubbleGroup()
        settleBubbleGroup()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun openOverflowPanel() {
        closeOverflowPanel()
        val remaining = conversationStates.entries
            .sortedByDescending { it.value.lastUpdated }
            .drop(HomePreferences.maxVisibleBubbles(this))
        if (remaining.isEmpty()) return

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dpToPx(10), dpToPx(10), dpToPx(10), dpToPx(10))
            background = roundedDrawable(
                Color.WHITE,
                dpToPx(18).toFloat(),
                Color.parseColor("#D1D5DB")
            )
            elevation = dpToPx(16).toFloat()
            setOnTouchListener { _, event ->
                if (event.actionMasked == MotionEvent.ACTION_OUTSIDE) {
                    closeOverflowPanel()
                    true
                } else {
                    false
                }
            }
        }
        remaining.forEach { (id, state) ->
            root.addView(TextView(this).apply {
                text = "${state.session.title.ifEmpty { state.session.appName }}  ·  ${state.session.appName}"
                textSize = 14f
                setTextColor(Color.parseColor("#111827"))
                setPadding(dpToPx(12), dpToPx(12), dpToPx(12), dpToPx(12))
                background = roundedDrawable(Color.parseColor("#F9FAFB"), dpToPx(12).toFloat())
                setOnClickListener {
                    closeOverflowPanel()
                    openFloatingCard(id)
                }
            }, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dpToPx(6) })
        }

        val width = min(resources.displayMetrics.widthPixels - dpToPx(24), dpToPx(300))
        val params = WindowManager.LayoutParams(
            width,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = ((resources.displayMetrics.widthPixels - width) / 2).coerceAtLeast(0)
            y = dpToPx(210)
        }
        overflowPanel = root
        try {
            windowManager?.addView(root, params)
        } catch (_: Exception) {
            overflowPanel = null
        }
    }

    private fun closeOverflowPanel() {
        overflowPanel?.let { safeRemoveOverlay(it) }
        overflowPanel = null
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createMultiBubble(id: String, state: ConversationState) {
        val bubbleSize = dpToPx(64)
        val bubble = FrameLayout(this).apply {
            elevation = dpToPx(10).toFloat()
            background = ovalDrawable(Color.parseColor("#1E88E5"))
        }
        val avatar = ImageView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            scaleType = ImageView.ScaleType.CENTER_CROP
            visibility = View.GONE
        }
        val initials = TextView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            gravity = Gravity.CENTER
            textSize = 19f
            setTextColor(Color.WHITE)
            paint.isFakeBoldText = true
        }
        val badge = TextView(this).apply {
            val badgeSize = dpToPx(21)
            layoutParams = FrameLayout.LayoutParams(badgeSize, badgeSize).apply {
                gravity = Gravity.BOTTOM or Gravity.END
            }
            gravity = Gravity.CENTER
            textSize = 10f
            setTextColor(Color.WHITE)
            paint.isFakeBoldText = true
        }
        bubble.addView(avatar)
        bubble.addView(initials)
        bubble.addView(badge)

        val params = WindowManager.LayoutParams(
            bubbleSize,
            bubbleSize,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = resources.displayMetrics.widthPixels - bubbleSize - dpToPx(16)
            y = nextMultiBubbleY(bubbleSize)
        }

        val entry = MultiBubble(bubble, avatar, initials, badge, params)
        multiBubbles[id] = entry
        updateMultiBubble(id, state)
        installMultiBubbleTouch(id, entry, bubbleSize)
        try {
            windowManager?.addView(bubble, params)
        } catch (_: Exception) {
            multiBubbles.remove(id)
            conversationStates.remove(id)
            Toast.makeText(this, "Could not show chat bubble", Toast.LENGTH_SHORT).show()
        }
    }

    private fun nextMultiBubbleY(bubbleSize: Int): Int {
        val top = dpToPx(120)
        val bottom = (resources.displayMetrics.heightPixels - bubbleSize - dpToPx(110)).coerceAtLeast(top)
        var candidate = top
        while (multiBubbles.values.any { abs(it.params.y - candidate) < bubbleSize }) {
            candidate += bubbleSize + dpToPx(10)
            if (candidate > bottom) {
                candidate = top + ((multiBubbles.size * dpToPx(18)) % (bottom - top + 1))
                break
            }
        }
        return candidate.coerceIn(top, bottom)
    }

    private fun updateMultiBubble(id: String, state: ConversationState) {
        val bubble = multiBubbles[id] ?: return
        val session = state.session
        val title = session.title.ifEmpty { session.appName }
        if (session.avatar != null) {
            bubble.avatar.setImageBitmap(getCircularBitmap(session.avatar))
            bubble.avatar.visibility = View.VISIBLE
            bubble.initials.visibility = View.GONE
        } else {
            bubble.avatar.visibility = View.GONE
            bubble.initials.text = getInitials(title)
            bubble.initials.visibility = View.VISIBLE
        }
        val (color, initial) = appBadgeStyle(session.appName)
        bubble.badge.text = initial
        bubble.badge.background = ovalDrawable(color, Color.WHITE)
        bubble.view.contentDescription = "Open $title from ${session.appName}"
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun installMultiBubbleTouch(id: String, bubble: MultiBubble, bubbleSize: Int) {
        var initialX = 0
        var initialY = 0
        var touchX = 0f
        var touchY = 0f
        var dragging = false

        bubble.view.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = bubble.params.x
                    initialY = bubble.params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    dragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaX = (event.rawX - touchX).toInt()
                    val deltaY = (event.rawY - touchY).toInt()
                    if (!dragging && Math.hypot(deltaX.toDouble(), deltaY.toDouble()) > dpToPx(8)) {
                        dragging = true
                        showRemoveTarget()
                    }
                    if (dragging) {
                        bubble.params.x = initialX + deltaX
                        bubble.params.y = initialY + deltaY
                        windowManager?.updateViewLayout(bubble.view, bubble.params)
                        highlightRemoveTarget(isOverRemoveTarget(bubble.params, bubbleSize))
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (dragging) {
                        if (isOverRemoveTarget(bubble.params, bubbleSize)) {
                            dismissMultiConversation(id)
                        } else {
                            snapMultiBubble(bubble, bubbleSize)
                        }
                        hideRemoveTarget()
                    } else {
                        openFloatingCard(id)
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    if (dragging) snapMultiBubble(bubble, bubbleSize)
                    hideRemoveTarget()
                    true
                }
                else -> false
            }
        }
    }

    private fun snapMultiBubble(bubble: MultiBubble, bubbleSize: Int) {
        val screenWidth = resources.displayMetrics.widthPixels
        val margin = dpToPx(16)
        bubble.params.x = if (bubble.params.x + bubbleSize / 2 < screenWidth / 2) {
            margin
        } else {
            screenWidth - bubbleSize - margin
        }
        bubble.params.y = bubble.params.y.coerceIn(
            dpToPx(36),
            (resources.displayMetrics.heightPixels - bubbleSize - dpToPx(36)).coerceAtLeast(dpToPx(36))
        )
        windowManager?.updateViewLayout(bubble.view, bubble.params)
    }

    private fun createRemoveTarget() {
        val size = dpToPx(92)
        val target = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            background = ovalDrawable(Color.parseColor("#374151"))
            elevation = dpToPx(12).toFloat()
            visibility = View.GONE
            addView(TextView(context).apply {
                text = "×"
                textSize = 30f
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                paint.isFakeBoldText = true
            })
            addView(TextView(context).apply {
                text = "Remove"
                textSize = 10f
                setTextColor(Color.WHITE)
            })
        }
        val params = WindowManager.LayoutParams(
            size,
            size,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dpToPx(24)
        }
        removeTarget = target
        removeTargetParams = params
        try {
            windowManager?.addView(target, params)
        } catch (_: Exception) {
            removeTarget = null
            removeTargetParams = null
        }
    }

    private fun showRemoveTarget() {
        removeTarget?.visibility = View.VISIBLE
        highlightRemoveTarget(false)
    }

    private fun hideRemoveTarget() {
        highlightRemoveTarget(false)
        removeTarget?.visibility = View.GONE
    }

    private fun highlightRemoveTarget(highlighted: Boolean) {
        removeTarget?.background = ovalDrawable(
            if (highlighted) Color.parseColor("#DC2626") else Color.parseColor("#374151")
        )
    }

    private fun isOverRemoveTarget(params: WindowManager.LayoutParams, bubbleSize: Int): Boolean {
        if (removeTarget == null) return false
        val targetSize = dpToPx(92)
        val centerX = resources.displayMetrics.widthPixels / 2f
        val centerY = resources.displayMetrics.heightPixels -
            (removeTargetParams?.y ?: dpToPx(24)) - targetSize / 2f
        return Math.hypot(
            (params.x + bubbleSize / 2f - centerX).toDouble(),
            (params.y + bubbleSize / 2f - centerY).toDouble()
        ) <= (targetSize + bubbleSize) / 2f
    }

    private fun dismissMultiConversation(id: String) {
        if (expandedConversationId == id) closeFloatingCard()
        conversationStates.remove(id)
        multiBubbles.remove(id)?.view?.let { safeRemoveOverlay(it) }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun openFloatingCard(id: String) {
        val state = conversationStates[id] ?: return
        closeFloatingCard()
        expandedConversationId = id

        val screenWidth = resources.displayMetrics.widthPixels
        val screenHeight = resources.displayMetrics.heightPixels
        val cardWidth = min(
            (screenWidth - dpToPx(88)).coerceAtLeast(dpToPx(260)),
            dpToPx(380)
        )
        val cardHeight = min(screenHeight - dpToPx(96), dpToPx(520))
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dpToPx(14), dpToPx(12), dpToPx(14), dpToPx(12))
            background = roundedDrawable(
                themeColor("#FFFFFF", "#23221D"),
                dpToPx(22).toFloat(),
                themeColor("#D1D5DB", "#454239")
            )
            elevation = dpToPx(18).toFloat()
            setOnTouchListener { _, event ->
                if (event.action == MotionEvent.ACTION_OUTSIDE) {
                    closeFloatingCard()
                    true
                } else {
                    false
                }
            }
        }

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        header.addView(createCardIdentity(state, dpToPx(40)))

        val titleColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f
            ).apply { leftMargin = dpToPx(10) }
        }
        cardTitleView = TextView(this).apply {
            textSize = 16f
            paint.isFakeBoldText = true
            setTextColor(themeColor("#111827", "#F8F6EE"))
            maxLines = 1
        }
        cardSubtitleView = TextView(this).apply {
            textSize = 11f
            setTextColor(themeColor("#6B7280", "#B9B5A9"))
            maxLines = 1
        }
        cardTitleView?.let { titleColumn.addView(it) }
        cardSubtitleView?.let { titleColumn.addView(it) }
        header.addView(titleColumn)
        root.addView(header)
        root.addView(View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dpToPx(1)
            ).apply {
                topMargin = dpToPx(10)
                bottomMargin = dpToPx(8)
            }
            setBackgroundColor(themeColor("#E5E7EB", "#36342D"))
        })

        cardMessagesView = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dpToPx(4), 0, dpToPx(6))
        }
        cardScrollView = ScrollView(this).apply {
            isFillViewport = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
            cardMessagesView?.let { addView(it) }
        }
        cardScrollView?.let { root.addView(it) }

        cardStatusView = TextView(this).apply {
            textSize = 10.5f
            setTextColor(themeColor("#6B7280", "#B9B5A9"))
            gravity = Gravity.CENTER
            setPadding(dpToPx(4), dpToPx(6), dpToPx(4), dpToPx(6))
        }
        cardStatusView?.let { root.addView(it) }

        val replyRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        cardInputView = EditText(this).apply {
            hint = "Reply from notification..."
            textSize = 13f
            setTextColor(themeColor("#111827", "#F8F6EE"))
            setHintTextColor(themeColor("#9CA3AF", "#AAA79F"))
            maxLines = 3
            setPadding(dpToPx(12), dpToPx(8), dpToPx(12), dpToPx(8))
            background = roundedDrawable(
                themeColor("#F9FAFB", "#2B2A24"),
                dpToPx(20).toFloat(),
                themeColor("#D1D5DB", "#454239")
            )
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f
            )
        }
        cardSendView = Button(this).apply {
            text = "Send"
            textSize = 12f
            setTextColor(Color.WHITE)
            paint.isFakeBoldText = true
            background = roundedDrawable(Color.parseColor("#2563EB"), dpToPx(18).toFloat())
            layoutParams = LinearLayout.LayoutParams(dpToPx(70), dpToPx(42)).apply {
                leftMargin = dpToPx(8)
            }
            setOnClickListener { sendFloatingReply(id) }
        }
        cardInputView?.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                updateFloatingSendState()
            }
            override fun afterTextChanged(s: Editable?) = Unit
        })
        cardInputView?.let { replyRow.addView(it) }
        cardSendView?.let { replyRow.addView(it) }
        root.addView(replyRow)

        val params = WindowManager.LayoutParams(
            cardWidth,
            cardHeight,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dpToPx(12).coerceAtMost((screenWidth - cardWidth).coerceAtLeast(0))
            y = dpToPx(54)
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }
        installCardDrag(header, root, params, cardWidth, cardHeight)
        floatingCard = root
        try {
            windowManager?.addView(root, params)
            bubbleGroupParams?.let { groupParams ->
                if (groupYBeforeCard == null) groupYBeforeCard = groupParams.y
                val groupHeight = bubbleGroup?.height?.takeIf { it > 0 } ?: dpToPx(64)
                val maxGroupY = (screenHeight - groupHeight).coerceAtLeast(0)
                groupParams.y = (params.y + cardHeight + dpToPx(16)).coerceAtMost(maxGroupY)
                bubbleGroup?.let { windowManager?.updateViewLayout(it, groupParams) }
            }
            renderFloatingCard()
        } catch (_: Exception) {
            floatingCard = null
            expandedConversationId = null
            Toast.makeText(this, "Could not open floating conversation", Toast.LENGTH_SHORT).show()
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun installCardDrag(
        handle: View,
        card: View,
        params: WindowManager.LayoutParams,
        cardWidth: Int,
        cardHeight: Int
    ) {
        var initialX = 0
        var initialY = 0
        var touchX = 0f
        var touchY = 0f
        handle.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val maxX = (resources.displayMetrics.widthPixels - cardWidth).coerceAtLeast(0)
                    val maxY = (resources.displayMetrics.heightPixels - cardHeight).coerceAtLeast(dpToPx(24))
                    params.x = (initialX + (event.rawX - touchX).toInt()).coerceIn(0, maxX)
                    params.y = (initialY + (event.rawY - touchY).toInt()).coerceIn(dpToPx(24), maxY)
                    windowManager?.updateViewLayout(card, params)
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> true
                else -> false
            }
        }
    }

    private fun createCardIdentity(state: ConversationState, size: Int): FrameLayout {
        val frame = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(size, size)
            background = ovalDrawable(Color.parseColor("#1E88E5"))
        }
        val session = state.session
        if (session.avatar != null) {
            frame.addView(ImageView(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                scaleType = ImageView.ScaleType.CENTER_CROP
                setImageBitmap(getCircularBitmap(session.avatar))
            })
        } else {
            frame.addView(TextView(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                gravity = Gravity.CENTER
                textSize = 13f
                setTextColor(Color.WHITE)
                paint.isFakeBoldText = true
                text = getInitials(session.title.ifEmpty { session.appName })
            })
        }
        return frame
    }

    private fun renderFloatingCard() {
        val state = expandedConversationId?.let { conversationStates[it] } ?: return
        val session = state.session
        val time = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date(session.timestamp))
        cardTitleView?.text = session.title.ifEmpty { session.appName }
        cardSubtitleView?.text = "${session.appName} · $time"
        cardMessagesView?.removeAllViews()
        if (state.messages.isEmpty()) {
            cardMessagesView?.addView(TextView(this).apply {
                text = "No message text was exposed by this notification."
                textSize = 13f
                setTextColor(themeColor("#6B7280", "#B9B5A9"))
                gravity = Gravity.CENTER
                setPadding(dpToPx(10), dpToPx(28), dpToPx(10), dpToPx(28))
            })
        } else {
            state.messages.forEach { cardMessagesView?.addView(createObservedMessageView(it)) }
        }

        val hasReply = session.replyAction != null && session.replyRemoteInput != null
        cardStatusView?.text = when {
            state.replyStatus != null -> state.replyStatus
            !state.notificationActive ->
                "Notification messages only. The notification was cleared, so reply is unavailable."
            hasReply ->
                "Notification messages only; older chat history is unavailable. Replies use the app's notification action, and delivery cannot be confirmed here."
            else ->
                "Notification messages only; older chat history is unavailable. This notification does not provide a supported reply action."
        }
        cardInputView?.isEnabled = true
        cardInputView?.hint = if (state.notificationActive && hasReply) {
            "Type a reply..."
        } else {
            "Write a draft..."
        }
        updateFloatingSendState()
        cardScrollView?.post { cardScrollView?.fullScroll(View.FOCUS_DOWN) }
    }

    private fun createObservedMessageView(message: ObservedMessage): LinearLayout {
        val time = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date(message.timestamp))
        val outgoing = message.direction == "outgoing"
        val unknown = message.direction == "unknown"
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = if (outgoing) Gravity.END else Gravity.START
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = dpToPx(8)
            }
        }
        if (!outgoing && !unknown) {
            val avatar = conversationStates[expandedConversationId]?.session?.avatar
            row.addView(ImageView(this).apply {
                layoutParams = LinearLayout.LayoutParams(dpToPx(28), dpToPx(28)).apply {
                    rightMargin = dpToPx(7)
                }
                if (avatar != null) {
                    setImageBitmap(getCircularBitmap(avatar))
                    scaleType = ImageView.ScaleType.CENTER_CROP
                } else {
                    setImageDrawable(
                        roundedDrawable(
                            themeColor("#D1D5DB", "#4A4840"),
                            dpToPx(14).toFloat()
                        )
                    )
                }
                contentDescription = message.sender ?: "Sender"
            })
        }
        row.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dpToPx(12), dpToPx(9), dpToPx(12), dpToPx(8))
            background = roundedDrawable(
                when {
                    outgoing -> themeColor("#DCFCE7", "#254032")
                    unknown -> themeColor("#FEF3C7", "#453A1B")
                    else -> themeColor("#F3F4F6", "#2B2A24")
                },
                dpToPx(15).toFloat()
            )
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                if (outgoing) leftMargin = dpToPx(42) else rightMargin = dpToPx(42)
            }
            if (!message.sender.isNullOrBlank() && !outgoing) {
                addView(TextView(context).apply {
                    text = message.sender
                    textSize = 10f
                    setTextColor(themeColor("#6B7280", "#B9B5A9"))
                })
            }
            addView(TextView(context).apply {
                text = message.text
                textSize = 13.5f
                setTextColor(themeColor("#1F2937", "#F8F6EE"))
            })
            addView(TextView(context).apply {
                text = when {
                    outgoing -> "$time · ${message.replyStatus ?: "reply attempted; delivery unconfirmed"}"
                    unknown -> "$time · direction unknown"
                    else -> "$time · from notification"
                }
                textSize = 9.5f
                setTextColor(themeColor("#9CA3AF", "#AAA79F"))
                gravity = Gravity.END
            })
        })
        return row
    }

    private fun updateFloatingSendState() {
        val state = expandedConversationId?.let { conversationStates[it] }
        val canReply = state?.notificationActive == true &&
            state.session.replyAction != null && state.session.replyRemoteInput != null
        val enabled = canReply && !cardInputView?.text.isNullOrBlank()
        cardSendView?.isEnabled = enabled
        cardSendView?.alpha = if (enabled) 1f else 0.5f
    }

    private fun sendFloatingReply(id: String) {
        val state = conversationStates[id] ?: return
        val text = cardInputView?.text?.toString()?.trim().orEmpty()
        if (text.isEmpty()) return
        val session = activeReplySessionForConversation(id)
        if (session == null) {
            state.replyStatus = "No active quick-reply action. Draft kept; open the source app to send."
            renderFloatingCard()
            return
        }

        val attempt = ChatNotificationListenerService.sendQuickReply(this, session, text)
        if (attempt.accepted) {
            cardInputView?.setText("")
            state.replyStatus =
                "Reply request handed to ${session.appName}; delivery is not confirmed."
            val timestamp = System.currentTimeMillis()
            val replyState = "submitted; delivery unconfirmed"
            state.messages.add(ObservedMessage(text, timestamp, "outgoing", null, replyState))
            try {
                ChatHistoryStore.get(this).recordOutgoing(id, text, timestamp, replyState)
            } catch (_: Exception) {
                state.replyStatus += " Local history could not be updated."
            }
        } else {
            state.replyStatus =
                "Reply failed (${attempt.code}). Draft kept; open the source app to send."
        }
        renderFloatingCard()
    }

    private fun activeReplySessionForConversation(
        conversationId: String
    ): ChatNotificationListenerService.NotificationSession? =
        ChatNotificationListenerService.activeSessions.values
            .asSequence()
            .filter { conversationIdFor(it) == conversationId }
            .filter { it.replyAction != null && it.replyRemoteInput != null }
            .maxByOrNull { it.timestamp }

    private fun closeFloatingCard() {
        val keyboard = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        cardInputView?.let {
            keyboard?.hideSoftInputFromWindow(it.windowToken, 0)
            it.clearFocus()
        }
        floatingCard?.let { safeRemoveOverlay(it) }
        floatingCard = null
        cardTitleView = null
        cardSubtitleView = null
        cardMessagesView = null
        cardScrollView = null
        cardStatusView = null
        cardInputView = null
        cardSendView = null
        expandedConversationId = null
        val previousGroupY = groupYBeforeCard
        groupYBeforeCard = null
        if (previousGroupY != null) {
            bubbleGroupParams?.let { params ->
                params.y = previousGroupY
                bubbleGroup?.let { group ->
                    try {
                        windowManager?.updateViewLayout(group, params)
                    } catch (_: Exception) {
                        // The service or overlay permission may be going away.
                    }
                }
            }
        }
    }

    private fun handleMultiDismissal(id: String) {
        mainHandler.post {
            val conversationId = notificationToConversation.remove(id) ?: return@post
            val state = conversationStates[conversationId] ?: return@post
            state.activeNotificationIds.remove(id)
            state.notificationActive = state.activeNotificationIds.isNotEmpty()
            state.replyStatus = null
            if (expandedConversationId == conversationId) renderFloatingCard()
        }
    }

    private fun appBadgeStyle(appName: String): Pair<Int, String> {
        return when (appName.lowercase()) {
            "whatsapp", "whatsapp business" -> Pair(Color.parseColor("#25D366"), "W")
            "telegram" -> Pair(Color.parseColor("#229ED9"), "T")
            "messenger" -> Pair(Color.parseColor("#0084FF"), "M")
            else -> Pair(Color.parseColor("#1E88E5"), "C")
        }
    }

    private fun ovalDrawable(color: Int, strokeColor: Int? = null): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
            strokeColor?.let { setStroke(dpToPx(1), it) }
        }
    }

    private fun roundedDrawable(
        color: Int,
        radius: Float,
        strokeColor: Int? = null
    ): GradientDrawable {
        return GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius
            strokeColor?.let { setStroke(dpToPx(1), it) }
        }
    }

    private fun themeColor(light: String, dark: String): Int =
        Color.parseColor(if (usesDarkTheme()) dark else light)

    private fun usesDarkTheme(): Boolean = when (HomePreferences.theme(this)) {
        HomePreferences.THEME_DARK -> true
        HomePreferences.THEME_SYSTEM ->
            resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
                Configuration.UI_MODE_NIGHT_YES
        else -> false
    }

    private fun safeRemoveOverlay(view: View) {
        try {
            if (view.isAttachedToWindow) windowManager?.removeView(view)
        } catch (_: Exception) {
            // The system may already have detached the overlay.
        }
    }

    private fun getInitials(title: String): String {
        val clean = title.trim()
        if (clean.isEmpty()) return "💬"
        val parts = clean.split("\\s+".toRegex())
        return if (parts.size >= 2 && parts[0].isNotEmpty() && parts[1].isNotEmpty()) {
            "${parts[0].first().uppercase()}${parts[1].first().uppercase()}"
        } else {
            clean.take(2).uppercase()
        }
    }

    private fun getCircularBitmap(bitmap: Bitmap): Bitmap {
        val output = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val color = -0xbdbdbe
        val paint = Paint().apply {
            isAntiAlias = true
            this.color = color
        }
        val rect = Rect(0, 0, bitmap.width, bitmap.height)
        val radius = bitmap.width.coerceAtMost(bitmap.height) / 2f
        canvas.drawCircle(bitmap.width / 2f, bitmap.height / 2f, radius, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(bitmap, rect, rect, paint)
        return output
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * resources.displayMetrics.density).toInt()
    }

    override fun onDestroy() {
        closeFloatingCard()
        closeOverflowPanel()
        bubbleGroup?.let { safeRemoveOverlay(it) }
        bubbleGroup = null
        bubbleGroupParams = null
        groupYBeforeCard = null
        notificationToConversation.clear()
        primaryConversationId = null
        multiBubbles.values.toList().forEach { safeRemoveOverlay(it.view) }
        multiBubbles.clear()
        conversationStates.clear()
        removeTarget?.let { safeRemoveOverlay(it) }
        removeTarget = null
        removeTargetParams = null
        isRunning = false
        Log.i(TAG, "bubble stage=SERVICE_DESTROYED")
        if (activeInstance == this) {
            activeInstance = null
        }
        overlayLayout?.let {
            if (it.isAttachedToWindow) {
                windowManager?.removeView(it)
            }
        }
        overlayLayout = null
        popupPanel = null
        windowManager = null
        super.onDestroy()
    }
}
