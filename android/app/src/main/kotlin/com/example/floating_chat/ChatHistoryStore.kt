package com.example.floating_chat

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale

class ChatHistoryStore private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DATABASE_NAME, null, DATABASE_VERSION) {

    data class StoredMessage(
        val text: String,
        val sender: String?,
        val timestamp: Long,
        val direction: String,
        val replyStatus: String?
    )

    data class ConversationSummary(
        val id: String,
        val appName: String,
        val packageName: String,
        val title: String,
        val latestText: String,
        val latestTimestamp: Long
    )

    data class ImportResult(val conversations: Int, val messages: Int)

    companion object {
        private const val DATABASE_NAME = "floating_chat_history.db"
        private const val DATABASE_VERSION = 1
        private const val BACKUP_VERSION = 1

        @Volatile
        private var instance: ChatHistoryStore? = null

        fun get(context: Context): ChatHistoryStore = instance ?: synchronized(this) {
            instance ?: ChatHistoryStore(context).also { instance = it }
        }

        fun conversationId(packageName: String, title: String, fallbackId: String): String {
            val identity = title.trim().lowercase(Locale.ROOT)
            return if (identity.isNotEmpty()) "$packageName|$identity" else "$packageName|$fallbackId"
        }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE conversations (
                id TEXT PRIMARY KEY,
                app_name TEXT NOT NULL,
                package_name TEXT NOT NULL,
                title TEXT NOT NULL,
                last_updated INTEGER NOT NULL,
                has_reply_action INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE TABLE messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                dedupe_key TEXT NOT NULL UNIQUE,
                conversation_id TEXT NOT NULL,
                sender TEXT,
                text TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                direction TEXT NOT NULL,
                reply_status TEXT,
                FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX messages_conversation_time ON messages(conversation_id, timestamp)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    @Synchronized
    fun recordObservedNotification(
        session: ChatNotificationListenerService.NotificationSession
    ): String {
        val conversationId = session.conversationId
        upsertConversation(
            conversationId,
            session.appName,
            session.packageName,
            session.title,
            session.timestamp,
            session.replyAction != null && session.replyRemoteInput != null
        )
        if (
            session.direction == "outgoing" &&
            reconcileObservedOutgoing(conversationId, session.text.trim(), session.timestamp)
        ) {
            return "OUTGOING_RECONCILED"
        }
        val inserted = insertMessage(
            conversationId = conversationId,
            sourceKey = listOf(
                "notification",
                session.packageName,
                session.title.trim(),
                session.timestamp.toString(),
                session.senderName.orEmpty().trim(),
                session.text.trim(),
                session.direction
            ).joinToString(":"),
            sender = if (session.direction == "incoming") {
                session.senderName ?: session.title.ifBlank { null }
            } else {
                null
            },
            text = session.text.trim(),
            timestamp = session.timestamp,
            direction = session.direction,
            replyStatus = if (session.direction == "outgoing") {
                "sent; observed in source notification"
            } else {
                null
            }
        )
        return if (inserted) "MESSAGE_INSERTED" else "MESSAGE_DEDUPED_OR_EMPTY"
    }

    @Synchronized
    fun recordOutgoing(
        conversationId: String,
        text: String,
        timestamp: Long,
        replyStatus: String
    ) {
        insertMessage(
            conversationId,
            "reply:$conversationId:$timestamp:$text",
            null,
            text.trim(),
            timestamp,
            "outgoing",
            replyStatus
        )
        writableDatabase.execSQL(
            "UPDATE conversations SET last_updated = MAX(last_updated, ?) WHERE id = ?",
            arrayOf<Any>(timestamp, conversationId)
        )
    }

    @Synchronized
    fun recentMessages(conversationId: String, limit: Int = 100): List<StoredMessage> {
        val result = mutableListOf<StoredMessage>()
        readableDatabase.query(
            "messages",
            arrayOf("text", "sender", "timestamp", "direction", "reply_status"),
            "conversation_id = ?",
            arrayOf(conversationId),
            null,
            null,
            "timestamp DESC, id DESC",
            limit.toString()
        ).use { cursor ->
            while (cursor.moveToNext()) {
                result.add(
                    StoredMessage(
                        text = cursor.getString(0),
                        sender = cursor.getString(1),
                        timestamp = cursor.getLong(2),
                        direction = cursor.getString(3),
                        replyStatus = cursor.getString(4)
                    )
                )
            }
        }
        return result.asReversed()
    }

    @Synchronized
    fun conversationSummaries(): List<ConversationSummary> {
        val result = mutableListOf<ConversationSummary>()
        readableDatabase.rawQuery(
            """
            SELECT c.id, c.app_name, c.package_name, c.title,
                   COALESCE(latest.text, '') AS latest_text,
                   COALESCE(latest.timestamp, c.last_updated) AS latest_timestamp
            FROM conversations c
            LEFT JOIN messages latest ON latest.id = (
                SELECT m.id
                FROM messages m
                WHERE m.conversation_id = c.id
                ORDER BY m.timestamp DESC, m.id DESC
                LIMIT 1
            )
            ORDER BY latest_timestamp DESC, c.id ASC
            """.trimIndent(),
            null
        ).use { cursor ->
            while (cursor.moveToNext()) {
                result.add(
                    ConversationSummary(
                        id = cursor.getString(0),
                        appName = cursor.getString(1),
                        packageName = cursor.getString(2),
                        title = cursor.getString(3),
                        latestText = cursor.getString(4),
                        latestTimestamp = cursor.getLong(5)
                    )
                )
            }
        }
        return result
    }

    @Synchronized
    fun packageNameForConversation(conversationId: String): String? {
        readableDatabase.query(
            "conversations",
            arrayOf("package_name"),
            "id = ?",
            arrayOf(conversationId),
            null,
            null,
            null,
            "1"
        ).use { cursor ->
            return if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }

    @Synchronized
    fun clearAll() {
        writableDatabase.beginTransaction()
        try {
            writableDatabase.delete("messages", null, null)
            writableDatabase.delete("conversations", null, null)
            writableDatabase.setTransactionSuccessful()
        } finally {
            writableDatabase.endTransaction()
        }
    }

    @Synchronized
    fun exportTo(context: Context, uri: Uri) {
        val root = JSONObject().put("format", "floating-chat-backup").put("version", BACKUP_VERSION)
        val conversations = JSONArray()
        readableDatabase.query("conversations", null, null, null, null, null, "last_updated ASC").use { c ->
            while (c.moveToNext()) {
                conversations.put(
                    JSONObject()
                        .put("id", c.getString(c.getColumnIndexOrThrow("id")))
                        .put("appName", c.getString(c.getColumnIndexOrThrow("app_name")))
                        .put("packageName", c.getString(c.getColumnIndexOrThrow("package_name")))
                        .put("title", c.getString(c.getColumnIndexOrThrow("title")))
                        .put("lastUpdated", c.getLong(c.getColumnIndexOrThrow("last_updated")))
                        .put("hasReplyAction", c.getInt(c.getColumnIndexOrThrow("has_reply_action")) == 1)
                )
            }
        }
        val messages = JSONArray()
        readableDatabase.query("messages", null, null, null, null, null, "timestamp ASC, id ASC").use { c ->
            while (c.moveToNext()) {
                messages.put(
                    JSONObject()
                        .put("dedupeKey", c.getString(c.getColumnIndexOrThrow("dedupe_key")))
                        .put("conversationId", c.getString(c.getColumnIndexOrThrow("conversation_id")))
                        .put("sender", c.getString(c.getColumnIndexOrThrow("sender")))
                        .put("text", c.getString(c.getColumnIndexOrThrow("text")))
                        .put("timestamp", c.getLong(c.getColumnIndexOrThrow("timestamp")))
                        .put("direction", c.getString(c.getColumnIndexOrThrow("direction")))
                        .put("replyStatus", c.getString(c.getColumnIndexOrThrow("reply_status")))
                )
            }
        }
        root.put("conversations", conversations)
            .put("messages", messages)
            .put("settings", HomePreferences.toJson(context))
        context.contentResolver.openOutputStream(uri, "wt")?.bufferedWriter()?.use { it.write(root.toString()) }
            ?: error("Could not open backup destination")
    }

    @Synchronized
    fun importFrom(context: Context, uri: Uri): ImportResult {
        val raw = context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            ?: error("Could not read backup")
        require(raw.length <= 25_000_000) { "Backup is too large" }
        val root = JSONObject(raw)
        require(root.optString("format") == "floating-chat-backup") { "Not a Floating Chat backup" }
        require(root.optInt("version", -1) == BACKUP_VERSION) { "Unsupported backup version" }
        val conversations = root.getJSONArray("conversations")
        val messages = root.getJSONArray("messages")
        require(conversations.length() <= 100_000 && messages.length() <= 1_000_000) { "Backup exceeds safe limits" }
        val importedSettings = root.optJSONObject("settings")?.let {
            HomePreferences.validateImportedSettings(it)
        }

        var conversationCount = 0
        var messageCount = 0
        writableDatabase.beginTransaction()
        try {
            for (index in 0 until conversations.length()) {
                val item = conversations.getJSONObject(index)
                val id = item.getString("id").takeIf { it.isNotBlank() } ?: error("Invalid conversation")
                upsertConversation(
                    id,
                    item.getString("appName"),
                    item.getString("packageName"),
                    item.getString("title"),
                    item.getLong("lastUpdated"),
                    item.optBoolean("hasReplyAction", false)
                )
                conversationCount++
            }
            for (index in 0 until messages.length()) {
                val item = messages.getJSONObject(index)
                val direction = item.getString("direction")
                require(direction in setOf("incoming", "outgoing", "unknown")) { "Invalid message direction" }
                val inserted = insertMessage(
                    item.getString("conversationId"),
                    "import:${item.getString("dedupeKey")}",
                    item.optString("sender").takeIf { it.isNotBlank() && it != "null" },
                    item.getString("text"),
                    item.getLong("timestamp"),
                    direction,
                    item.optString("replyStatus").takeIf { it.isNotBlank() && it != "null" }
                )
                if (inserted) messageCount++
            }
            writableDatabase.setTransactionSuccessful()
        } finally {
            writableDatabase.endTransaction()
        }
        if (importedSettings != null) {
            HomePreferences.applyImportedSettings(context, importedSettings)
        }
        return ImportResult(conversationCount, messageCount)
    }

    private fun upsertConversation(
        id: String,
        appName: String,
        packageName: String,
        title: String,
        timestamp: Long,
        hasReplyAction: Boolean
    ) {
        val values = ContentValues().apply {
            put("id", id)
            put("app_name", appName)
            put("package_name", packageName)
            put("title", title)
            put("last_updated", timestamp)
            put("has_reply_action", if (hasReplyAction) 1 else 0)
        }
        writableDatabase.insertWithOnConflict(
            "conversations",
            null,
            values,
            SQLiteDatabase.CONFLICT_IGNORE
        )
        writableDatabase.execSQL(
            """
            UPDATE conversations
            SET app_name = ?, package_name = ?, title = ?,
                last_updated = MAX(last_updated, ?),
                has_reply_action = MAX(has_reply_action, ?)
            WHERE id = ?
            """.trimIndent(),
            arrayOf<Any>(appName, packageName, title, timestamp, if (hasReplyAction) 1 else 0, id)
        )
    }

    private fun insertMessage(
        conversationId: String,
        sourceKey: String,
        sender: String?,
        text: String,
        timestamp: Long,
        direction: String,
        replyStatus: String?
    ): Boolean {
        if (text.isBlank()) return false
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(sourceKey.toByteArray())
            .joinToString("") { "%02x".format(it) }
        val values = ContentValues().apply {
            put("dedupe_key", digest)
            put("conversation_id", conversationId)
            put("sender", sender)
            put("text", text)
            put("timestamp", timestamp)
            put("direction", direction)
            put("reply_status", replyStatus)
        }
        return writableDatabase.insertWithOnConflict(
            "messages",
            null,
            values,
            SQLiteDatabase.CONFLICT_IGNORE
        ) != -1L
    }

    private fun reconcileObservedOutgoing(
        conversationId: String,
        text: String,
        observedTimestamp: Long
    ): Boolean {
        if (text.isBlank()) return false
        val windowStart = observedTimestamp - 120_000L
        val windowEnd = observedTimestamp + 120_000L
        var matchingId: Long? = null
        readableDatabase.rawQuery(
            """
            SELECT id
            FROM messages
            WHERE conversation_id = ?
              AND direction = 'outgoing'
              AND text = ?
              AND timestamp BETWEEN ? AND ?
            ORDER BY
              CASE WHEN reply_status LIKE '%unconfirmed%' THEN 0 ELSE 1 END,
              ABS(timestamp - ?) ASC,
              id DESC
            LIMIT 1
            """.trimIndent(),
            arrayOf(
                conversationId,
                text,
                windowStart.toString(),
                windowEnd.toString(),
                observedTimestamp.toString()
            )
        ).use { cursor ->
            if (cursor.moveToFirst()) matchingId = cursor.getLong(0)
        }
        val id = matchingId ?: return false
        val values = ContentValues().apply {
            put("reply_status", "sent; observed in source notification")
        }
        writableDatabase.update("messages", values, "id = ?", arrayOf(id.toString()))
        return true
    }
}
