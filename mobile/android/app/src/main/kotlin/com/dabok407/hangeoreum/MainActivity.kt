package com.dabok407.hangeoreum

import android.app.LocaleManager
import android.content.Intent
import android.content.res.Resources
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var subscriptions: SubscriptionBridge? = null
    private var backupFiles: BackupDocumentBridge? = null
    private var widgetChannel: MethodChannel? = null
    private var widgetBridgeReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        subscriptions = SubscriptionBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        backupFiles = BackupDocumentBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dabok407.hangeoreum/widget",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCalendarPreferences" -> result.success(calendarPreferences())
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
        backupFiles?.close()
        backupFiles = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @Deprecated("Required by the document picker activity result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (backupFiles?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
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

    private fun calendarPreferences(): Map<String, Any> {
        // Read the system locale rather than this Activity's app-language override.
        // This is a local formatting preference, not the device's physical location.
        val systemLocale = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getSystemService(LocaleManager::class.java)?.systemLocales?.let { locales ->
                if (locales.isEmpty) null else locales[0]
            }
        } else {
            null
        } ?: if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            Resources.getSystem().configuration.locales.let { locales ->
                if (locales.isEmpty) Locale.ROOT else locales[0]
            }
        } else {
            @Suppress("DEPRECATION")
            Resources.getSystem().configuration.locale ?: Locale.ROOT
        }
        // Android's regional preference may be carried by the Unicode "fw" key.
        // Honour it explicitly because older Calendar implementations can ignore it.
        val preferredFirstDay = when (systemLocale.getUnicodeLocaleType("fw")) {
            "sun" -> 0
            "mon" -> 1
            "tue" -> 2
            "wed" -> 3
            "thu" -> 4
            "fri" -> 5
            "sat" -> 6
            else -> null
        }
        return mapOf(
            "regionCode" to systemLocale.country,
            "firstDayOfWeek" to (preferredFirstDay
                ?: (Calendar.getInstance(systemLocale).firstDayOfWeek - Calendar.SUNDAY)),
        )
    }
}
