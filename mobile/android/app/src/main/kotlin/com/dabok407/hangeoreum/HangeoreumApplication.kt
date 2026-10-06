package com.dabok407.hangeoreum

import android.app.Application
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper

/** Observe headless Flutter preference writes without needing an Activity/engine hook. */
class HangeoreumApplication : Application() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val refresh = Runnable { HangeoreumWidgetProvider.updateAll(this) }
    // SharedPreferences keeps listeners weakly; retain the observer for this process.
    private val snapshotListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == "flutter.widget_snapshot") {
            mainHandler.removeCallbacks(refresh)
            mainHandler.post(refresh)
        }
    }

    override fun onCreate() {
        super.onCreate()
        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .registerOnSharedPreferenceChangeListener(snapshotListener)
    }
}
