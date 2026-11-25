package com.chorequest.applock

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.Process

/**
 * Which app is in front, from Android's usage events (AL-3). Needs Usage
 * access, which a grown-up turns on for ChoreQuest in the phone's settings.
 *
 * Each look reads the events since the last one (with a few seconds' overlap,
 * as events can arrive late) and keeps the newest app to come to the front.
 * With no new events, the app in front has not changed.
 */
class ForegroundApp(private val context: Context) {
    private val usage = context.getSystemService(UsageStatsManager::class.java)
    private var lastLook = System.currentTimeMillis() - LOOK_BACK_MS
    private var inFront: String? = null

    fun current(): String? {
        val now = System.currentTimeMillis()
        val from = maxOf(lastLook - OVERLAP_MS, now - LOOK_BACK_MS)
        lastLook = now
        val events = usage?.queryEvents(from, now) ?: return inFront
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.eventType == RESUMED) inFront = event.packageName
        }
        return inFront
    }

    /** Forget the app in front, such as when the screen turns off. */
    fun forget() {
        inFront = null
    }

    companion object {
        // ACTIVITY_RESUMED from Android 10, MOVE_TO_FOREGROUND before: the
        // same number.
        private const val RESUMED = 1
        private const val OVERLAP_MS = 5_000L
        private const val LOOK_BACK_MS = 60 * 60_000L

        fun hasUsageAccess(context: Context): Boolean {
            val ops = context.getSystemService(AppOpsManager::class.java) ?: return false
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            }
            return if (mode == AppOpsManager.MODE_DEFAULT) {
                context.checkSelfPermission(android.Manifest.permission.PACKAGE_USAGE_STATS) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
            } else {
                mode == AppOpsManager.MODE_ALLOWED
            }
        }
    }
}
