package com.chorequest.applock

import android.annotation.SuppressLint
import android.content.Context
import android.provider.Settings
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.UUID

/**
 * What App Lock keeps on this phone between runs (AL-3): whether it is on,
 * the household and ticket its reports carry, the server's address, and this
 * phone's rules (package to earned_time or grown_ups_only).
 *
 * Kept in the app's no-backup folder, so a phone restored from a backup does
 * not arrive with another phone's ticket. It must be readable with no one
 * signed in and with Flutter not running: after a restart, the boot receiver
 * starts the watcher from this alone.
 */
class AppLockConfig private constructor(private val file: File) {
    @Volatile
    var enabled = false
        private set
    @Volatile
    var householdId = 0L
        private set
    @Volatile
    var ticket: String? = null
        private set
    @Volatile
    var baseUrl: String? = null
        private set
    @Volatile
    var rules: Map<String, String> = emptyMap()
        private set
    var deviceKeyFallback: String? = null
        private set

    @Synchronized
    fun turnOn(householdId: Long, ticket: String, baseUrl: String) {
        enabled = true
        this.householdId = householdId
        this.ticket = ticket
        this.baseUrl = baseUrl.trimEnd('/')
        save()
    }

    /** Rules are kept: turning App Lock on again finds them on the server too. */
    @Synchronized
    fun turnOff() {
        enabled = false
        ticket = null
        save()
    }

    @Synchronized
    fun setRules(rules: Map<String, String>) {
        this.rules = rules.filterValues { it == EARNED_TIME || it == GROWN_UPS_ONLY }
        save()
    }

    @Synchronized
    fun fallbackKey(): String {
        deviceKeyFallback?.let { return it }
        val made = UUID.randomUUID().toString().replace("-", "")
        deviceKeyFallback = made
        save()
        return made
    }

    @Synchronized
    private fun load() {
        try {
            if (!file.exists()) return
            val json = JSONObject(file.readText())
            enabled = json.optBoolean("enabled", false)
            householdId = json.optLong("household_id", 0L)
            ticket = json.optString("ticket").ifEmpty { null }
            baseUrl = json.optString("base_url").ifEmpty { null }
            deviceKeyFallback = json.optString("device_key_fallback").ifEmpty { null }
            val raw = json.optJSONObject("rules")
            rules = if (raw == null) emptyMap() else raw.keys().asSequence().associateWith { raw.getString(it) }
        } catch (_: Exception) {
            // Unreadable: start from nothing. A grown-up turns App Lock on again.
        }
    }

    private fun save() {
        val json = JSONObject()
            .put("enabled", enabled)
            .put("household_id", householdId)
            .put("ticket", ticket ?: "")
            .put("base_url", baseUrl ?: "")
            .put("device_key_fallback", deviceKeyFallback ?: "")
            .put("rules", JSONObject(rules))
        file.parentFile?.mkdirs()
        val temp = File(file.path + ".tmp")
        temp.writeText(json.toString())
        if (!temp.renameTo(file)) {
            file.writeText(json.toString())
            temp.delete()
        }
    }

    companion object {
        const val EARNED_TIME = "earned_time"
        const val GROWN_UPS_ONLY = "grown_ups_only"

        @Volatile
        private var instance: AppLockConfig? = null

        fun of(context: Context): AppLockConfig =
            instance ?: synchronized(this) {
                instance ?: AppLockConfig(File(context.applicationContext.noBackupFilesDir, "app_lock.json"))
                    .also { it.load(); instance = it }
            }

        /**
         * This phone's key for App Lock's rules and reports: a hash of
         * Android's id for this app on this phone, so a reinstall finds the
         * same rules, and the id itself never leaves the phone. Android's id
         * is already different for every app, so no other app can match it.
         * A phone without one gets a random key, kept here.
         */
        @SuppressLint("HardwareIds")
        fun deviceKey(context: Context): String {
            val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
            val source = if (androidId.isNullOrBlank()) of(context).fallbackKey() else androidId
            val digest = MessageDigest.getInstance("SHA-256").digest("chorequest-app-lock|$source".toByteArray())
            return digest.joinToString("") { "%02x".format(it) }.take(32)
        }
    }
}
