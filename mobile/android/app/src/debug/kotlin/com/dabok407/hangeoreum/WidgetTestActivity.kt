package com.dabok407.hangeoreum

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.graphics.Color
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/** Debug-only launcher-like host for emulator widget rendering and tap tests. */
class WidgetTestActivity : Activity() {
    private lateinit var host: AppWidgetHost
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
        widget.postDelayed({
            val heading = widget.findViewById<View>(R.id.widget_header)
            checkNotNull(heading) { "Widget RemoteViews failed to inflate." }
            intent.getStringExtra("expectedTitle")?.let { expected ->
                val titles = mutableListOf<String>()
                collectTitles(widget, titles)
                check(expected in titles) { "Expected '$expected', rendered $titles." }
            }
            Log.i(TAG, "WIDGET_RENDER_OK:${width}x$height")
        }, 2000)
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

    companion object { private const val TAG = "HangeoreumWidgetTest" }
}
