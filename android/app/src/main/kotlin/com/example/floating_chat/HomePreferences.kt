package com.example.floating_chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object HomePreferences {
    const val MODE_ALL = "all"
    const val MODE_CUSTOM = "custom"

    private const val PREFS_NAME = "floating_chat_home"
    private const val KEY_SOURCE_MODE = "source_mode"
    private const val KEY_SELECTED_PACKAGES = "selected_packages"
    private const val KEY_SERVICE_ENABLED = "service_enabled"
    private const val KEY_SHOW_UNREAD_COUNT = "show_unread_count"
    private const val KEY_MAX_VISIBLE_BUBBLES = "max_visible_bubbles"
    private const val KEY_BUBBLE_SIZE = "bubble_size"
    private const val KEY_SNAP_TO_EDGES = "snap_to_edges"
    private const val KEY_VIBRATION_FEEDBACK = "vibration_feedback"
    private const val KEY_THEME = "theme"

    const val BUBBLE_SIZE_SMALL = "small"
    const val BUBBLE_SIZE_MEDIUM = "medium"
    const val BUBBLE_SIZE_LARGE = "large"
    const val THEME_LIGHT = "light"
    const val THEME_DARK = "dark"
    const val THEME_SYSTEM = "system"

    fun sourceMode(context: Context): String {
        val stored = prefs(context).getString(KEY_SOURCE_MODE, MODE_ALL)
        return if (stored == MODE_CUSTOM) MODE_CUSTOM else MODE_ALL
    }

    fun setSourceMode(context: Context, mode: String) {
        require(mode == MODE_ALL || mode == MODE_CUSTOM) { "Unknown notification source mode" }
        if (mode == MODE_CUSTOM) {
            require(selectedPackages(context).isNotEmpty()) {
                "Select at least one app before enabling Custom apps"
            }
        }
        prefs(context).edit().putString(KEY_SOURCE_MODE, mode).apply()
    }

    fun selectedPackages(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_SELECTED_PACKAGES, emptySet())
            ?.filterTo(linkedSetOf()) { isValidPackageName(it) && it != context.packageName }
            ?: emptySet()

    fun setSelectedPackages(context: Context, packageNames: Collection<String>) {
        val clean = packageNames
            .asSequence()
            .filter { isValidPackageName(it) && it != context.packageName }
            .distinct()
            .take(250)
            .toCollection(linkedSetOf())
        prefs(context).edit().putStringSet(KEY_SELECTED_PACKAGES, clean).apply()
        if (clean.isEmpty() && sourceMode(context) == MODE_CUSTOM) {
            prefs(context).edit().putString(KEY_SOURCE_MODE, MODE_ALL).apply()
        }
    }

    fun isServiceEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_SERVICE_ENABLED, false)

    fun setServiceEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_SERVICE_ENABLED, enabled).apply()
    }

    fun showUnreadCount(context: Context): Boolean =
        prefs(context).getBoolean(KEY_SHOW_UNREAD_COUNT, true)

    fun setShowUnreadCount(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_SHOW_UNREAD_COUNT, enabled).apply()
    }

    fun maxVisibleBubbles(context: Context): Int =
        prefs(context).getInt(KEY_MAX_VISIBLE_BUBBLES, 3).coerceIn(1, 5)

    fun setMaxVisibleBubbles(context: Context, count: Int) {
        require(count in 1..5) { "Max visible bubbles must be between 1 and 5" }
        prefs(context).edit().putInt(KEY_MAX_VISIBLE_BUBBLES, count).apply()
    }

    fun bubbleSize(context: Context): String {
        val stored = prefs(context).getString(KEY_BUBBLE_SIZE, BUBBLE_SIZE_MEDIUM)
        return if (stored in VALID_BUBBLE_SIZES) stored!! else BUBBLE_SIZE_MEDIUM
    }

    fun setBubbleSize(context: Context, size: String) {
        require(size in VALID_BUBBLE_SIZES) { "Unknown bubble size" }
        prefs(context).edit().putString(KEY_BUBBLE_SIZE, size).apply()
    }

    fun snapToEdges(context: Context): Boolean =
        prefs(context).getBoolean(KEY_SNAP_TO_EDGES, true)

    fun setSnapToEdges(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_SNAP_TO_EDGES, enabled).apply()
    }

    fun vibrationFeedback(context: Context): Boolean =
        prefs(context).getBoolean(KEY_VIBRATION_FEEDBACK, true)

    fun setVibrationFeedback(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_VIBRATION_FEEDBACK, enabled).apply()
    }

    fun theme(context: Context): String {
        val stored = prefs(context).getString(KEY_THEME, THEME_LIGHT)
        return if (stored in VALID_THEMES) stored!! else THEME_LIGHT
    }

    fun setTheme(context: Context, theme: String) {
        require(theme in VALID_THEMES) { "Unknown theme" }
        prefs(context).edit().putString(KEY_THEME, theme).apply()
    }

    fun allowsPackage(context: Context, packageName: String): Boolean {
        if (packageName == context.packageName) return false
        return sourceMode(context) != MODE_CUSTOM || selectedPackages(context).contains(packageName)
    }

    fun toJson(context: Context): JSONObject = JSONObject()
        .put("notificationMode", sourceMode(context))
        .put("selectedPackages", JSONArray(selectedPackages(context).sorted()))
        .put("floatingChatEnabled", isServiceEnabled(context))
        .put("showUnreadCount", showUnreadCount(context))
        .put("maxVisibleBubbles", maxVisibleBubbles(context))
        .put("bubbleSize", bubbleSize(context))
        .put("snapToEdges", snapToEdges(context))
        .put("vibrationFeedback", vibrationFeedback(context))

    fun validateImportedSettings(settings: JSONObject): ImportedSettings {
        val mode = settings.optString("notificationMode", MODE_ALL)
        require(mode == MODE_ALL || mode == MODE_CUSTOM) { "Invalid notification mode" }

        val selectedArray = settings.optJSONArray("selectedPackages") ?: JSONArray()
        require(selectedArray.length() <= 250) { "Too many selected applications" }
        val selected = linkedSetOf<String>()
        for (index in 0 until selectedArray.length()) {
            val packageName = selectedArray.getString(index)
            require(isValidPackageName(packageName)) { "Invalid application package" }
            selected.add(packageName)
        }
        require(mode != MODE_CUSTOM || selected.isNotEmpty()) {
            "Custom apps mode requires at least one selected application"
        }
        val maxVisibleBubbles = settings.optInt("maxVisibleBubbles", 3)
        require(maxVisibleBubbles in 1..5) { "Invalid max visible bubbles" }
        val bubbleSize = settings.optString("bubbleSize", BUBBLE_SIZE_MEDIUM)
        require(bubbleSize in VALID_BUBBLE_SIZES) { "Invalid bubble size" }
        return ImportedSettings(
            mode = mode,
            selectedPackages = selected,
            serviceEnabled = settings.optBoolean("floatingChatEnabled", false),
            showUnreadCount = settings.optBoolean("showUnreadCount", true),
            maxVisibleBubbles = maxVisibleBubbles,
            bubbleSize = bubbleSize,
            snapToEdges = settings.optBoolean("snapToEdges", true),
            vibrationFeedback = settings.optBoolean("vibrationFeedback", true)
        )
    }

    fun applyImportedSettings(context: Context, settings: ImportedSettings) {
        val selected = settings.selectedPackages.filterTo(linkedSetOf()) { it != context.packageName }
        prefs(context).edit()
            .putString(KEY_SOURCE_MODE, if (settings.mode == MODE_CUSTOM && selected.isEmpty()) MODE_ALL else settings.mode)
            .putStringSet(KEY_SELECTED_PACKAGES, selected)
            .putBoolean(KEY_SERVICE_ENABLED, settings.serviceEnabled)
            .putBoolean(KEY_SHOW_UNREAD_COUNT, settings.showUnreadCount)
            .putInt(KEY_MAX_VISIBLE_BUBBLES, settings.maxVisibleBubbles)
            .putString(KEY_BUBBLE_SIZE, settings.bubbleSize)
            .putBoolean(KEY_SNAP_TO_EDGES, settings.snapToEdges)
            .putBoolean(KEY_VIBRATION_FEEDBACK, settings.vibrationFeedback)
            .apply()
    }

    data class ImportedSettings(
        val mode: String,
        val selectedPackages: Set<String>,
        val serviceEnabled: Boolean,
        val showUnreadCount: Boolean,
        val maxVisibleBubbles: Int,
        val bubbleSize: String,
        val snapToEdges: Boolean,
        val vibrationFeedback: Boolean
    )

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun isValidPackageName(value: String): Boolean =
        value.length in 3..255 && PACKAGE_NAME.matches(value)

    private val PACKAGE_NAME = Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$")
    private val VALID_BUBBLE_SIZES = setOf(
        BUBBLE_SIZE_SMALL,
        BUBBLE_SIZE_MEDIUM,
        BUBBLE_SIZE_LARGE
    )
    private val VALID_THEMES = setOf(THEME_LIGHT, THEME_DARK, THEME_SYSTEM)
}
