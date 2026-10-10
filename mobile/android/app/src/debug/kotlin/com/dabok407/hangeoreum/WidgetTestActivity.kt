package com.dabok407.hangeoreum

import android.app.Activity
import android.app.NotificationManager
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.graphics.Color
import android.graphics.Rect
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.util.Locale

/** Debug-only launcher-like host for emulator widget rendering and tap tests. */
class WidgetTestActivity : Activity() {
    private lateinit var host: AppWidgetHost
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        verifyWidgetLanguageResolution()
        // Alarm delivery has already been verified; keep its heads-up banner out
        // of the widget render screenshots.
        getSystemService(NotificationManager::class.java)?.apply {
            cancel(100001)
            cancel(100002)
        }
        host = AppWidgetHost(this, 7201)
        widgetId = host.allocateAppWidgetId()
        val manager = AppWidgetManager.getInstance(this)
        val width = intent.getIntExtra("widgetWidth", 330).coerceIn(180, 450)
        val height = intent.getIntExtra("widgetHeight", 330).coerceIn(130, 500)
        val options = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, width)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, width)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, height)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, height)
        }
        if (!manager.bindAppWidgetIdIfAllowed(
                widgetId,
                ComponentName(this, HangeoreumWidgetProvider::class.java),
                options,
            )) {
            val warning = TextView(this).apply {
                text = "위젯 테스트 권한 필요\nadb shell appwidget grantbind --package com.dabok407.hangeoreum"
                setTextColor(Color.BLACK)
                setPadding(dp(24), dp(24), dp(24), dp(24))
            }
            setContentView(warning)
            Log.e(TAG, "WIDGET_BIND_FAILED")
            return
        }
        val info = manager.getAppWidgetInfo(widgetId)
        checkNotNull(info) { "Widget provider metadata is unavailable." }
        val widget = host.createView(this, widgetId, info)
        // AppWidget options describe the provider's content area. A launcher
        // allocates host padding separately; this test uses the content size.
        widget.setPadding(0, 0, 0, 0)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.rgb(236, 237, 240))
            setPadding(dp(16), dp(56), dp(16), dp(24))
        }
        root.addView(TextView(this).apply {
            text = "Android 홈 위젯 · ${width}×${height}dp"
            setTextColor(Color.rgb(70, 75, 80))
            textSize = 14f
            setPadding(0, 0, 0, dp(20))
        })
        root.addView(widget, FrameLayout.LayoutParams(dp(width), dp(height)))
        setContentView(root)
        HangeoreumWidgetProvider.updateAll(this)
        // Validate the RemoteViews have actually inflated in a real OS widget host.
        fun verifyRendered(attempt: Int) {
            val heading = widget.findViewById<View>(R.id.widget_header)
            checkNotNull(heading) { "Widget RemoteViews failed to inflate." }
            intent.getStringExtra("expectedTitle")?.let { expected ->
                val titles = mutableListOf<String>()
                collectTitles(widget, titles)
                if (expected !in titles && attempt < 20) {
                    widget.postDelayed({ verifyRendered(attempt + 1) }, 500)
                    return
                }
                val shared = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                    .getString("flutter.widget_snapshot", null)
                val native = getSharedPreferences("hangeoreum_widget", MODE_PRIVATE)
                    .getString("tasks", null)
                check(expected in titles) { "Expected '$expected', rendered $titles; shared=$shared; native=$native." }
            }
            verifyTaskTextBounds(widget)
            Log.i(TAG, "WIDGET_RENDER_OK:${width}x$height")
        }
        widget.postDelayed({ verifyRendered(0) }, 500)
    }

    override fun onStart() {
        super.onStart()
        if (::host.isInitialized) host.startListening()
    }

    override fun onStop() {
        if (::host.isInitialized) host.stopListening()
        super.onStop()
    }

    override fun onDestroy() {
        if (::host.isInitialized && widgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
            host.deleteAppWidgetId(widgetId)
        }
        super.onDestroy()
    }

    private fun collectTitles(view: View, values: MutableList<String>) {
        if (view is TextView && view.id == R.id.widget_task_title) values.add(view.text.toString())
        if (view is android.view.ViewGroup) {
            for (index in 0 until view.childCount) collectTitles(view.getChildAt(index), values)
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun verifyWidgetLanguageResolution() {
        val korean = Locale.KOREAN
        val english = Locale.US
        check(HangeoreumWidgetProvider.resolveLanguage("system", "ko", english) == "en")
        check(HangeoreumWidgetProvider.resolveLanguage("system", "en", korean) == "ko")
        check(HangeoreumWidgetProvider.resolveLanguage("system", "ko", Locale.FRENCH) == "en")
        check(HangeoreumWidgetProvider.resolveLanguage("ko", "en", english) == "ko")
        check(HangeoreumWidgetProvider.resolveLanguage("en", "ko", korean) == "en")
        check(HangeoreumWidgetProvider.resolveLanguage(null, "ko", english) == "ko")
        check(HangeoreumWidgetProvider.resolveLanguage(null, "en", korean) == "en")
        check(HangeoreumWidgetProvider.resolveLanguage(null, null, korean) == "ko")
        check(HangeoreumWidgetProvider.resolveLanguage("invalid", "invalid", english) == "en")
        Log.i(TAG, "WIDGET_LANGUAGE_OK")
    }

    private fun verifyTaskTextBounds(view: View) {
        if (view is TextView && view.isShown &&
            (view.id == R.id.widget_task_title || view.id == R.id.widget_task_due)) {
            val bounds = Rect()
            check(view.height > 0 && view.getLocalVisibleRect(bounds) && bounds.height() == view.height) {
                "Widget text is vertically clipped: '${view.text}', height=${view.height}, visible=$bounds"
            }
        }
        if (view is android.view.ViewGroup) {
            for (index in 0 until view.childCount) verifyTaskTextBounds(view.getChildAt(index))
        }
    }

    companion object { private const val TAG = "HangeoreumWidgetTest" }
}
