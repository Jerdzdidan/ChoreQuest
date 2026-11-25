package com.chorequest.applock

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import com.chorequest.MainActivity
import com.chorequest.R
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * App Lock's watcher (AL-3): a foreground service that looks at which app
 * is in front twice a second and brings ChoreQuest's lock screen over a
 * locked one.
 *
 * - An Earned time app stays open only for minutes the server has written
 *   (rule 9). The first is bought by the lock screen; each one after it is
 *   bought here, a few seconds before the one before runs out, while the
 *   app is still in front. No answer means no minute: the app locks when
 *   the paid one ends.
 * - A grown-up's unlock lasts while the app is in front, and ends once it
 *   has been away for a little while, or the screen turns off.
 * - It reports to the server every 15 minutes and whenever a permission
 *   changes, and tells whoever holds the phone when a permission App Lock
 *   needs is taken away (rule 10, AL-4).
 *
 * Its notification is the countdown while a child spends minutes, and says
 * "App Lock is on" otherwise. Started again by Android if it is stopped
 * (START_STICKY), and after a restart by [AppLockBootReceiver].
 */
class AppLockService : Service() {
    private lateinit var config: AppLockConfig
    private lateinit var foreground: ForegroundApp
    private lateinit var thread: HandlerThread
    private lateinit var handler: Handler
    private val network = Executors.newSingleThreadExecutor()
    private val notifications by lazy { getSystemService(NotificationManager::class.java) }
    private val deviceKey by lazy { AppLockConfig.deviceKey(this) }

    // Touched on the watcher's thread only.
    private var lastLaunchPkg: String? = null
    private var lastLaunchAt = 0L
    private var lastHealthAt = 0L
    private var lastReportAt = 0L
    private var nextReportAt = 0L
    private var lastReported: String? = null
    private var shownProblem: String? = null
    private var shownCountdown = -1L
    private var refusedShown = false

    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            handler.post { endForScreenOff() }
        }
    }

    private val tick = object : Runnable {
        override fun run() {
            try {
                step()
            } catch (e: Exception) {
                Log.w(TAG, "App Lock could not look at the phone", e)
            }
            handler.postDelayed(this, LOOK_EVERY_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        config = AppLockConfig.of(this)
        foreground = ForegroundApp(this)
        createChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Foreground first, every time: Android requires it of a service
        // started with startForegroundService, even one about to stop.
        if (!goForeground() || !config.enabled) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!running) {
            startWatching()
        } else {
            handler.post {
                shownCountdown = -1L
                // Asked to look again now: a permission may have just changed.
                if (intent?.action == ACTION_CHECK_NOW) lastHealthAt = 0L
            }
        }
        return START_STICKY
    }

    private fun startWatching() {
        thread = HandlerThread("chorequest-app-lock").also { it.start() }
        handler = Handler(thread.looper)
        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenOff, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenOff, filter)
        }
        running = true
        handler.post(tick)
    }

    override fun onDestroy() {
        if (running) {
            running = false
            handler.removeCallbacksAndMessages(null)
            try {
                unregisterReceiver(screenOff)
            } catch (_: Exception) {
                // Not registered: nothing to undo.
            }
            thread.quitSafely()
        }
        network.shutdown()
        super.onDestroy()
    }

    private fun step() {
        val now = System.currentTimeMillis()
        if (!config.enabled) {
            stopSelf()
            return
        }
        if (now - lastHealthAt >= HEALTH_EVERY_MS) {
            lastHealthAt = now
            checkHealth(now)
        }
        val power = getSystemService(PowerManager::class.java)
        if (power != null && !power.isInteractive) return

        val inFront = foreground.current() ?: return
        val rule = config.rules[inFront]
        val reason: String? = synchronized(AppLockState) {
            follow(inFront, now)
            when {
                inFront == packageName -> null
                rule == null -> null
                allowed(inFront, rule, now) -> null
                else -> reasonFor(inFront, now)
            }
        }
        updateCountdown()
        if (reason != null) showLockScreen(inFront, reason, now)
    }

    /** Keeps the grown-up's pass and the child's minutes up to date. Holds AppLockState's lock. */
    private fun follow(inFront: String, now: Long) {
        AppLockState.grownUp?.let { pass ->
            if (pass.pkg == inFront) pass.lastInFront = now
            val gone = if (pass.lastInFront == 0L) {
                now - pass.grantedAt > PASS_FIRST_MS
            } else {
                now - pass.lastInFront > PASS_AWAY_MS
            }
            if (gone) AppLockState.grownUp = null
        }

        val session = AppLockState.child ?: return
        if (session.more && !session.requesting && inFront == session.pkg && now >= session.paidUntil - EARLY_MS) {
            buyMinute(session)
        }
        if (!session.more && !session.requesting && !session.warned) {
            session.warned = true
            warnLastMinute(session)
        }
        val grace = if (session.requesting) GRACE_MS else 0L
        if (now >= session.paidUntil + grace) {
            if (inFront == session.pkg) AppLockState.endedBecause[session.pkg] = session.endReason to now
            endChild(session)
        }
    }

    private fun allowed(pkg: String, rule: String, now: Long): Boolean {
        if (AppLockState.grownUp?.pkg == pkg) return true
        val session = AppLockState.child ?: return false
        val grace = if (session.requesting) GRACE_MS else 0L
        return session.pkg == pkg && rule == AppLockConfig.EARNED_TIME && now < session.paidUntil + grace
    }

    private fun reasonFor(pkg: String, now: Long): String {
        val (reason, at) = AppLockState.endedBecause[pkg] ?: return AppLockState.REASON_LOCKED
        return if (now - at < REASON_KEPT_MS) reason else AppLockState.REASON_LOCKED
    }

    private fun showLockScreen(pkg: String, reason: String, now: Long) {
        if (pkg == lastLaunchPkg && now - lastLaunchAt < RELAUNCH_MS) return
        lastLaunchPkg = pkg
        lastLaunchAt = now
        synchronized(AppLockState) {
            AppLockState.pending = AppLockState.LockRequest(pkg, reason, now)
        }
        try {
            // Allowed from the background because ChoreQuest may display over
            // other apps, which App Lock asks for when it is turned on.
            startActivity(
                Intent(this, MainActivity::class.java)
                    .setAction(ACTION_LOCK)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            )
        } catch (e: Exception) {
            Log.w(TAG, "App Lock could not show its lock screen", e)
        }
    }

    /** The next minute, from the server. Holds AppLockState's lock. */
    private fun buyMinute(session: AppLockState.ChildSession) {
        val base = config.baseUrl
        if (base == null) {
            session.more = false
            session.endReason = AppLockState.REASON_OFFLINE
            return
        }
        session.requesting = true
        val body = JSONObject()
            .put("device_key", deviceKey)
            .put("package", session.pkg)
            .put("opening", false)
        network.execute {
            val answer = AppLockHttp.post("$base/screen-time/minutes", body, session.token)
            synchronized(AppLockState) {
                session.requesting = false
                when (answer.status) {
                    201 -> {
                        session.paidUntil += MINUTE_MS
                        session.balanceAfter = answer.body?.optInt("balance_minutes", 0) ?: 0
                        if (session.balanceAfter <= 0) session.more = false
                    }
                    // No answer: no minute. The app locks when the paid one ends.
                    0 -> {
                        session.more = false
                        session.endReason = AppLockState.REASON_OFFLINE
                    }
                    // 409: no time left. Anything else (the app is no longer
                    // Earned time, the token is gone): no more minutes either.
                    else -> session.more = false
                }
            }
        }
    }

    /** Holds AppLockState's lock. */
    private fun endChild(session: AppLockState.ChildSession) {
        if (AppLockState.child === session) AppLockState.child = null
        notifications?.cancel(WARNING_ID)
        val base = config.baseUrl ?: return
        // After any minute still being bought: the network thread runs in order.
        network.execute { AppLockHttp.post("$base/logout", JSONObject(), session.token) }
    }

    private fun endForScreenOff() {
        synchronized(AppLockState) {
            AppLockState.grownUp = null
            AppLockState.child?.let { endChild(it) }
        }
        updateCountdown()
    }

    private fun warnLastMinute(session: AppLockState.ChildSession) {
        val label = label(this, session.pkg)
        if (session.endReason == AppLockState.REASON_OFFLINE) {
            alert(WARNING_ID, "$label locks in less than a minute", "ChoreQuest can't reach the server, so no more minutes can be spent.")
        } else {
            alert(WARNING_ID, "1 minute left on $label", "Then it locks until more time is earned.")
        }
    }

    private fun updateCountdown() {
        val countdown: Pair<String, Long>? = synchronized(AppLockState) {
            AppLockState.child?.let { it.pkg to it.paidUntil + it.balanceAfter * MINUTE_MS }
        }
        val end = countdown?.second ?: 0L
        if (end == shownCountdown) return
        shownCountdown = end
        notifications?.notify(WATCH_ID, watching(countdown?.let { label(this, it.first) to it.second }))
    }

    private fun checkHealth(now: Long) {
        val checks = checks(this)
        showProblem(checks.filterValues { !it }.keys)
        val json = JSONObject(checks as Map<*, *>).toString()
        val due = json != lastReported || now - lastReportAt >= REPORT_EVERY_MS
        if (due && now >= nextReportAt) report(checks, json, now)
    }

    private fun report(checks: Map<String, Boolean>, json: String, now: Long) {
        val base = config.baseUrl ?: return
        val ticket = config.ticket ?: return
        nextReportAt = now + RETRY_MS
        val body = JSONObject()
            .put("household_id", config.householdId)
            .put("device_key", deviceKey)
            .put("ticket", ticket)
            .put("checks", JSONObject(checks as Map<*, *>))
        network.execute {
            val answer = AppLockHttp.post("$base/app-lock/status", body)
            handler.post {
                when {
                    answer.status in 200..299 -> {
                        lastReported = json
                        lastReportAt = now
                        nextReportAt = 0L
                        refusedShown = false
                    }
                    // The server no longer knows this phone. Locked apps stay
                    // locked; only a grown-up turning App Lock off here stops it.
                    answer.status == 403 -> {
                        lastReported = json
                        lastReportAt = now
                        if (!refusedShown) {
                            refusedShown = true
                            alert(
                                REFUSED_ID,
                                "App Lock can't reach your account",
                                "Locked apps stay locked. A grown-up can turn App Lock on again in ChoreQuest.",
                            )
                        }
                    }
                    // Not reached: try again after RETRY_MS.
                    else -> Unit
                }
            }
        }
    }

    private fun showProblem(missing: Set<String>) {
        val key = missing.sorted().joinToString(",")
        if (key == shownProblem) return
        shownProblem = key
        if (missing.isEmpty()) {
            notifications?.cancel(PROBLEM_ID)
            return
        }
        val lines = CHECK_NAMES.filterKeys { it in missing }.values.joinToString(" ")
        val stops = "usage_access" in missing || "overlay" in missing
        alert(
            PROBLEM_ID,
            if (stops) "App Lock has stopped working" else "App Lock needs a grown-up",
            "$lines A grown-up can turn it back on in ChoreQuest.",
        )
    }

    private fun goForeground(): Boolean = try {
        val notification = watching(null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(WATCH_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(WATCH_ID, notification)
        }
        true
    } catch (e: Exception) {
        // Android refused a foreground service just now; the next start of
        // ChoreQuest, or the next restart of the phone, tries again.
        Log.w(TAG, "App Lock could not start", e)
        false
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        notifications?.createNotificationChannel(
            NotificationChannel(WATCH_CHANNEL, "App Lock", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shows App Lock is on, and the time left on a locked app."
                setShowBadge(false)
            },
        )
        notifications?.createNotificationChannel(
            NotificationChannel(ALERT_CHANNEL, "App Lock warnings", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "One minute left, and App Lock needing a grown-up."
            },
        )
    }

    @Suppress("DEPRECATION")
    private fun builder(channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, channel) else Notification.Builder(this)

    private fun openChoreQuest(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** The watcher's own notification: the countdown, or "App Lock is on". */
    @Suppress("DEPRECATION")
    private fun watching(countdown: Pair<String, Long>?): Notification {
        val builder = builder(WATCH_CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setContentIntent(openChoreQuest())
            .setPriority(Notification.PRIORITY_LOW)
        return if (countdown == null) {
            builder
                .setContentTitle("App Lock is on")
                .setContentText("Locked apps open with earned time or a grown-up's PIN.")
                .setShowWhen(false)
                .build()
        } else {
            builder
                .setContentTitle("${countdown.first}: time left")
                .setContentText("Earned time, spent one minute at a time.")
                .setWhen(countdown.second)
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
                .build()
        }
    }

    @Suppress("DEPRECATION")
    private fun alert(id: Int, title: String, text: String) {
        notifications?.notify(
            id,
            builder(ALERT_CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setContentIntent(openChoreQuest())
                .setAutoCancel(true)
                .setPriority(Notification.PRIORITY_HIGH)
                .build(),
        )
    }

    companion object {
        private const val TAG = "ChoreQuestAppLock"

        const val ACTION_LOCK = "com.chorequest.action.APP_LOCK"
        const val ACTION_CHECK_NOW = "com.chorequest.action.APP_LOCK_CHECK"

        private const val WATCH_CHANNEL = "chorequest_app_lock"
        private const val ALERT_CHANNEL = "chorequest_app_lock_alerts"
        private const val WATCH_ID = 7301
        private const val WARNING_ID = 7302
        private const val PROBLEM_ID = 7303
        private const val REFUSED_ID = 7304

        /** Twice a second, as the plan asks. */
        private const val LOOK_EVERY_MS = 500L
        private const val MINUTE_MS = 60_000L

        /** The next minute is bought this long before the paid one ends... */
        private const val EARLY_MS = 5_000L

        /** ...and the app stays open this long past it while the answer is on its way. */
        private const val GRACE_MS = 3_000L

        private const val PASS_FIRST_MS = 20_000L
        private const val PASS_AWAY_MS = 10_000L
        private const val RELAUNCH_MS = 1_500L
        private const val REASON_KEPT_MS = 15_000L
        private const val HEALTH_EVERY_MS = 5_000L
        private const val REPORT_EVERY_MS = 15 * 60_000L
        private const val RETRY_MS = 2 * 60_000L

        /** What each missing permission means, in plain words. */
        private val CHECK_NAMES = linkedMapOf(
            "usage_access" to "Usage access is off, so App Lock cannot see which app is open.",
            "overlay" to "Display over other apps is off, so the lock screen cannot open.",
            "notifications" to "Notifications are off, so the countdown cannot show.",
            "battery" to "Battery saving may stop App Lock while the phone sleeps.",
        )

        @Volatile
        var running = false
            private set

        fun start(context: Context, checkNow: Boolean = false) {
            val intent = Intent(context, AppLockService::class.java)
            if (checkNow) intent.action = ACTION_CHECK_NOW
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AppLockService::class.java))
        }

        /** What App Lock needs on this phone, each on or off. */
        fun checks(context: Context): Map<String, Boolean> {
            val notifications = context.getSystemService(NotificationManager::class.java)
            val power = context.getSystemService(PowerManager::class.java)
            return linkedMapOf(
                "usage_access" to ForegroundApp.hasUsageAccess(context),
                "overlay" to Settings.canDrawOverlays(context),
                "notifications" to (notifications?.areNotificationsEnabled() ?: false),
                "battery" to (power?.isIgnoringBatteryOptimizations(context.packageName) ?: false),
            )
        }

        @Suppress("DEPRECATION")
        fun label(context: Context, pkg: String): String = try {
            val pm = context.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (_: Exception) {
            pkg
        }
    }
}
