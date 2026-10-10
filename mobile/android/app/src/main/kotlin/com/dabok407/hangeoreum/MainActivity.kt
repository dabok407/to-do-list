package com.dabok407.hangeoreum

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var subscriptions: SubscriptionBridge? = null
    private var widgetChannel: MethodChannel? = null
    private var widgetBridgeReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        subscriptions = SubscriptionBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dabok407.hangeoreum/widget",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        val payload = call.arguments as? Map<*, *>
                        val tasks = payload?.get("tasks") as? List<*>
                        if (tasks == null) {
                            result.error("INVALID_PAYLOAD", "A tasks list is required.", null)
                        } else {
                            HangeoreumWidgetProvider.saveSnapshot(this, tasks, payload?.get("languageCode") as? String, payload?.get("languagePreference") as? String)
                            result.success(null)
                        }
                    }
                    "getLaunchUri" -> {
                        // Dart registers its listener before asking for the initial URI.
                        widgetBridgeReady = true
                        val uri = widgetLaunchUri(intent)
                        if (uri != null) intent.data = null
                        result.success(uri)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        subscriptions?.close()
        subscriptions = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        widgetLaunchUri(intent)?.let { uri ->
            if (widgetBridgeReady) {
                widgetChannel?.invokeMethod("launchUri", uri)
                intent.data = null
            }
        }
    }

    private fun widgetLaunchUri(intent: Intent?): String? = intent?.data?.takeIf {
        it.scheme == "hangeoreum" && it.host == "task"
    }?.toString()
}
