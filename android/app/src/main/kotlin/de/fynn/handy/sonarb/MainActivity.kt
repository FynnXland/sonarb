package de.fynn.handy.sonarb

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "sonarb/maps_nav").setMethodCallHandler { call, result ->
            when (call.method) {
                "granted" -> result.success(NavNotificationListener.granted(this))
                "setEnabled" -> {
                    NavNotificationListener.setEnabled(this, call.arguments == true)
                    result.success(null)
                }
                "openSettings" -> {
                    try {
                        startActivity(NavNotificationListener.settingsIntent(this))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "latest" -> result.success(NavNotificationListener.latest?.toMap())
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "sonarb/maps_nav/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    NavNotificationListener.sink = events
                }

                override fun onCancel(arguments: Any?) {
                    NavNotificationListener.sink = null
                }
            },
        )
    }
}
