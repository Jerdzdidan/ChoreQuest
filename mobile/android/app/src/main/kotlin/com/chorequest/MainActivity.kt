package com.chorequest

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
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
    }
}
