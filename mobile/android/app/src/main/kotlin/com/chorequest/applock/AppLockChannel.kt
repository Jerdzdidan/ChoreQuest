package com.chorequest.applock

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * App Lock between Flutter and Android (AL-3): the permissions it needs,
 * turning it on and off, this phone's rules and apps, and the lock screen's
 * side of an unlock. Tells Flutter "lock" when the watcher brings the lock
 * screen up over a locked app.
 */
class AppLockChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.chorequest/app_lock")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val config get() = AppLockConfig.of(activity)

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error("app_lock", e.message, null)
            }
        }
    }

    /** From MainActivity, for every intent it is given. */
    fun onIntent(intent: Intent?) {
        if (intent?.action == AppLockService.ACTION_LOCK) channel.invokeMethod("lock", null)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deviceKey" -> result.success(AppLockConfig.deviceKey(activity))
            "status" -> result.success(
                mapOf(
                    "enabled" to config.enabled,
                    "running" to AppLockService.running,
                    "checks" to AppLockService.checks(activity),
                    "phone_name" to "${Build.MANUFACTURER} ${Build.MODEL}".trim().take(60),
                ),
            )
            "open" -> result.success(open(call.argument<String>("what")))
            "turnOn" -> {
                config.turnOn(
                    householdId = call.argument<Number>("household_id")?.toLong() ?: 0L,
                    ticket = call.argument<String>("ticket") ?: "",
                    baseUrl = call.argument<String>("base_url") ?: "",
                )
                AppLockService.start(activity, checkNow = true)
                result.success(null)
            }
            "turnOff" -> {
                config.turnOff()
                synchronized(AppLockState) {
                    AppLockState.child = null
                    AppLockState.grownUp = null
                    AppLockState.pending = null
                }
                AppLockService.stop(activity)
                result.success(null)
            }
            // At every start and return of ChoreQuest: a watcher Android
            // stopped is started again, and checks permissions at once.
            "ensureRunning" -> {
                if (config.enabled) AppLockService.start(activity, checkNow = true)
                result.success(config.enabled)
            }
            "setRules" -> {
                config.setRules(call.argument<Map<String, String>>("rules") ?: emptyMap())
                result.success(null)
            }
            "installedApps" -> inBackground(result) { installedApps() }
            "appIcon" -> {
                val pkg = call.argument<String>("package")
                val size = (call.argument<Int>("size") ?: 96).coerceIn(24, 256)
                inBackground(result) { if (pkg == null) null else icon(pkg, size) }
            }
            "appLabel" -> result.success(call.argument<String>("package")?.let { AppLockService.label(activity, it) })
            "pendingLock" -> result.success(
                synchronized(AppLockState) {
                    AppLockState.pending?.let {
                        mapOf(
                            "package" to it.pkg,
                            "label" to AppLockService.label(activity, it.pkg),
                            "reason" to it.reason,
                            "setting" to (config.rules[it.pkg] ?: AppLockConfig.EARNED_TIME),
                        )
                    }
                },
            )
            "clearLock" -> {
                synchronized(AppLockState) { AppLockState.pending = null }
                result.success(null)
            }
            // The lock screen bought the first minute (opening: true); the
            // watcher buys the rest.
            "startChildSession" -> {
                val pkg = call.argument<String>("package")
                val token = call.argument<String>("token")
                if (pkg == null || token == null) {
                    result.error("app_lock", "package and token are needed", null)
                    return
                }
                val replaced = synchronized(AppLockState) {
                    val before = AppLockState.child
                    AppLockState.child = AppLockState.ChildSession(
                        pkg = pkg,
                        token = token,
                        paidUntil = System.currentTimeMillis() + 60_000L,
                        balanceAfter = call.argument<Int>("balance_after") ?: 0,
                    )
                    AppLockState.pending = null
                    before
                }
                if (replaced != null && replaced.token != token) signOut(replaced.token)
                result.success(null)
            }
            "allowGrownUp" -> {
                val pkg = call.argument<String>("package")
                synchronized(AppLockState) {
                    AppLockState.grownUp = pkg?.let { AppLockState.GrownUpPass(it, System.currentTimeMillis()) }
                    AppLockState.pending = null
                }
                result.success(null)
            }
            "openApp" -> {
                val launch = call.argument<String>("package")?.let { activity.packageManager.getLaunchIntentForPackage(it) }
                if (launch == null) {
                    result.success(false)
                } else {
                    activity.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
            }
            // Away from a locked app without opening it.
            "goHome" -> {
                activity.startActivity(
                    Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Usage access or Display over other apps: the screen that turns it on. */
    private fun open(what: String?): String {
        val pkg = Uri.fromParts("package", activity.packageName, null)
        val candidates = when (what) {
            "usage_access" -> listOf(
                Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, pkg),
                Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS),
            )
            "overlay" -> listOf(
                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${activity.packageName}")),
                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION),
            )
            else -> emptyList()
        }
        for (intent in candidates) {
            try {
                activity.startActivity(intent)
                return "opened"
            } catch (_: Exception) {
                // Not on this phone: try the next.
            }
        }
        return "unavailable"
    }

    /** Every app with a home-screen icon, but ChoreQuest, by name. Read here, never sent. */
    private fun installedApps(): List<Map<String, String>> {
        val pm = activity.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val found = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(launcher, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(launcher, 0)
        }
        return found
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != activity.packageName }
            .distinctBy { it.first }
            .sortedBy { it.second.lowercase() }
            .map { mapOf("package" to it.first, "label" to it.second) }
    }

    private fun icon(pkg: String, size: Int): ByteArray? = try {
        val drawable = activity.packageManager.getApplicationIcon(pkg)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    } catch (_: Exception) {
        null
    }

    private fun signOut(token: String) {
        val base = config.baseUrl ?: return
        worker.execute { AppLockHttp.post("$base/logout", JSONObject(), token) }
    }

    private fun <T> inBackground(result: MethodChannel.Result, work: () -> T) {
        worker.execute {
            val value = try {
                work()
            } catch (_: Exception) {
                null
            }
            main.post { result.success(value) }
        }
    }
}
