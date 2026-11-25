package com.chorequest.applock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Starts App Lock's watcher again after the phone restarts, or after
 * ChoreQuest is updated, when App Lock is on (AL-3). Both broadcasts come
 * from Android only.
 */
class AppLockBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        if (!AppLockConfig.of(context).enabled) return
        try {
            AppLockService.start(context, checkNow = true)
        } catch (e: Exception) {
            // Refused for now; the next time ChoreQuest opens, it tries again.
            Log.w("ChoreQuestAppLock", "App Lock could not start after a restart", e)
        }
    }
}
