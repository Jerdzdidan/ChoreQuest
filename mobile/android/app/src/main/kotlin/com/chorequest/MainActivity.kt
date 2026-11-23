package com.chorequest

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.hardware.usb.UsbManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // The phone's timezone as an IANA name such as "Asia/Manila", so the
        // server can count days at local midnight. Reading it needs no
        // permission: it is the setting the phone's clock already uses.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.chorequest/timezone")
            .setMethodCallHandler { call, result ->
                if (call.method == "localTimezone") {
                    result.success(TimeZone.getDefault().id)
                } else {
                    result.notImplemented()
                }
            }

        // The "ready for alarms" checklist (DV-1): what quest alarms need on
        // this phone, read from Android itself, and one tap to fix each.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.chorequest/readiness")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "check" -> result.success(readiness())
                    "fix" -> fix(call.argument<String>("row"), result)
                    "openMakerBattery" -> result.success(if (open(makerBatteryScreens())) "opened" else "unavailable")
                    else -> result.notImplemented()
                }
            }

        // Cameras (DV-8): whether this phone can use a USB camera at all, so
        // the app can say so plainly, and a signal whenever one may have been
        // plugged in or out. The camera plugin then lists what is there.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.chorequest/cameras")
            .setMethodCallHandler { call, result ->
                if (call.method == "usbCameraSupport") {
                    result.success(packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_EXTERNAL))
                } else {
                    result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.chorequest/camera-changes")
            .setStreamHandler(CameraChanges(this))
    }

    private fun readiness(): Map<String, Any> {
        val notifications = getSystemService(NotificationManager::class.java)
        val alarms = getSystemService(AlarmManager::class.java)
        val power = getSystemService(PowerManager::class.java)
        return mapOf(
            "notifications" to notifications.areNotificationsEnabled(),
            // Before Android 12 exact alarms needed no permission; before 14
            // the full-screen page could not be switched off.
            "exact_alarms" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()),
            "full_screen" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE || notifications.canUseFullScreenIntent()),
            "battery" to power.isIgnoringBatteryOptimizations(packageName),
            "camera" to (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED),
            "maker_battery" to makerBatteryScreens().isNotEmpty(),
        )
    }

    private val packageUri get() = Uri.fromParts("package", packageName, null)

    private fun appDetails() = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri)

    private fun appNotifications() =
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)

    private fun fix(row: String?, result: MethodChannel.Result) {
        when (row) {
            "notifications" ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    ask(Manifest.permission.POST_NOTIFICATIONS, listOf(appNotifications(), appDetails()), result)
                } else {
                    result.success(opened(listOf(appNotifications(), appDetails())))
                }
            "camera" -> ask(Manifest.permission.CAMERA, listOf(appDetails()), result)
            "exact_alarms" -> result.success(
                opened(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        listOf(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, packageUri), appDetails())
                    } else {
                        listOf(appDetails())
                    },
                ),
            )
            "full_screen" -> result.success(
                opened(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        listOf(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, packageUri), appNotifications())
                    } else {
                        listOf(appNotifications())
                    },
                ),
            )
            // The list of apps battery saving leaves alone. Asking directly
            // would need one more permission, and the manifest gains only what
            // the alarm package asks for (DV-1).
            "battery" -> result.success(
                opened(listOf(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS), appDetails())),
            )
            else -> result.notImplemented()
        }
    }

    /** Opens the first screen this phone has; false when none would open. */
    private fun open(candidates: List<Intent>): Boolean {
        for (intent in candidates) {
            try {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: Exception) {
                // Not on this phone, or not open to other apps: try the next.
            }
        }
        return false
    }

    private fun opened(candidates: List<Intent>) = if (open(candidates)) "opened" else "unavailable"

    /**
     * Some makers' own battery managers stop a sleeping app whatever Android
     * says. Where the maker is known, these are its "start on its own" or
     * battery screens, best first. Unchecked on most of these phones; a
     * screen that is missing is skipped.
     */
    private fun makerBatteryScreens(): List<Intent> {
        val maker = Build.MANUFACTURER.lowercase()
        val screens = when {
            maker in setOf("xiaomi", "redmi", "poco") -> listOf(
                "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            )
            maker in setOf("huawei", "honor") -> listOf(
                "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
            )
            maker in setOf("oppo", "realme", "oneplus") -> listOf(
                "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
                "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
                "com.oneplus.security" to "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
            )
            maker in setOf("vivo", "iqoo") -> listOf(
                "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
            )
            maker == "samsung" -> listOf(
                "com.samsung.android.lool" to "com.samsung.android.sm.battery.ui.BatteryActivity",
                "com.samsung.android.lool" to "com.samsung.android.sm.ui.battery.BatteryActivity",
            )
            maker == "asus" -> listOf(
                "com.asus.mobilemanager" to "com.asus.mobilemanager.autostart.AutoStartActivity",
                "com.asus.mobilemanager" to "com.asus.mobilemanager.powersaver.PowerSaverSettings",
            )
            else -> emptyList()
        }
        return screens.map { (pkg, activity) -> Intent().setComponent(ComponentName(pkg, activity)) }
    }

    // A permission row: Android's own prompt while it will still show one,
    // then the app's settings once it will not (denied for good).
    private var asking: Triple<String, List<Intent>, MethodChannel.Result>? = null

    private fun ask(permission: String, settings: List<Intent>, result: MethodChannel.Result) {
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success("granted")
            return
        }
        if (asking != null) {
            result.success("busy")
            return
        }
        asking = Triple(permission, settings, result)
        requestPermissions(arrayOf(permission), ASK_PERMISSION)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != ASK_PERMISSION) return
        val (permission, settings, result) = asking ?: return
        asking = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        when {
            granted -> result.success("granted")
            // No prompt was shown, or it will not be again: only settings can.
            !shouldShowRequestPermissionRationale(permission) -> result.success(opened(settings))
            else -> result.success("denied")
        }
    }

    private companion object {
        const val ASK_PERMISSION = 4210
    }
}

/**
 * Tells Flutter that the cameras may have changed: a USB device attached or
 * detached, or Android saying a camera came or went. It says nothing about
 * which; the app lists them again. Only while Flutter listens.
 */
private class CameraChanges(private val activity: Activity) : EventChannel.StreamHandler {
    private val cameras = activity.getSystemService(CameraManager::class.java)
    private var sink: EventChannel.EventSink? = null

    private val usb = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            sink?.success("usb")
        }
    }

    private val availability = object : CameraManager.AvailabilityCallback() {
        override fun onCameraAvailable(cameraId: String) {
            sink?.success("available")
        }

        override fun onCameraUnavailable(cameraId: String) {
            sink?.success("unavailable")
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        // From the system only; nothing else may send these to the app.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(usb, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(usb, filter)
        }
        cameras.registerAvailabilityCallback(availability, Handler(Looper.getMainLooper()))
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        try {
            activity.unregisterReceiver(usb)
        } catch (_: IllegalArgumentException) {
            // Never registered.
        }
        cameras.unregisterAvailabilityCallback(availability)
    }
}
