package com.dabok407.hangeoreum

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/** A local snapshot of the Flutter database. Widget taps always enter the app. */
class HangeoreumWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        update(context, manager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            ACTION_REFRESH -> updateAll(context)
        }
    }

    companion object {
        const val ACTION_REFRESH = "com.dabok407.hangeoreum.WIDGET_REFRESH"
        private const val PREFERENCES = "hangeoreum_widget"
        private const val SNAPSHOT = "tasks"
        private const val FLUTTER_PREFERENCES = "FlutterSharedPreferences"
        private const val SHARED_SNAPSHOT = "flutter.widget_snapshot"
        private val INK = Color.rgb(39, 43, 48)
        private val RED = Color.rgb(143, 48, 58)

        fun saveSnapshot(context: Context, tasks: List<*>) {
            // Save synchronously before notifying launcher processes of the update.
            val snapshot = JSONArray()
            tasks.forEach { value ->
                val task = value as? Map<*, *> ?: return@forEach
                val id = task["id"] as? String ?: return@forEach
                val title = task["title"] as? String ?: return@forEach
                val due = (task["due"] as? Number)?.toLong() ?: return@forEach
                snapshot.put(JSONObject().apply {
                    put("id", id)
                    put("taskId", task["taskId"] as? String ?: id)
                    put("title", title)
                    put("due", due)
                    put("priority", (task["priority"] as? Number)?.toInt() ?: 0)
                    put("status", task["status"] as? String ?: "pending")
                    put("smallStep", task["smallStep"] as? String ?: "")
                    (task["expiresAt"] as? Number)?.let { put("expiresAt", it.toLong()) }
                })
            }
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
                .putString(SNAPSHOT, snapshot.toString()).commit()
            // The legacy shared_preferences file is also accessible in WorkManager's
            // headless engine. Keep one canonical snapshot across UI/background writes.
            val sharedSnapshot = JSONObject().apply {
                put("updatedAt", System.currentTimeMillis())
                put("tasks", snapshot)
            }
            context.getSharedPreferences(FLUTTER_PREFERENCES, Context.MODE_PRIVATE).edit()
                .putString(SHARED_SNAPSHOT, sharedSnapshot.toString()).commit()
            updateAll(context)
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, HangeoreumWidgetProvider::class.java),
            )
            ids.forEach { update(context, manager, it) }
        }

        private fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val now = System.currentTimeMillis()
            val tasks = readTasks(context).filter {
                it.optString("status") != "completed" && it.optString("status") != "skipped" &&
                    (it.optLong("expiresAt") == 0L || it.optLong("expiresAt") > now)
            }.sortedWith(compareBy<JSONObject> {
                when {
                    it.optString("status") == "progressing" -> 0
                    it.optLong("due") < now -> 1
                    else -> 2
                }
            }.thenBy {
                if (it.optLong("due") < now) -it.optInt("priority") else 0
            }.thenBy { it.optLong("due") }.thenBy { -it.optInt("priority") })
                .distinctBy { it.optString("taskId").ifEmpty { it.optString("id") } }

            val minHeight = manager.getAppWidgetOptions(id)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 220)
            val capacity = when {
                minHeight >= 315 -> 3
                minHeight >= 260 -> 2
                else -> 1
            }
            val views = RemoteViews(context.packageName, R.layout.widget_hangeoreum)
            views.setTextViewText(
                R.id.widget_date,
                SimpleDateFormat("M월 d일 EEEE", Locale.KOREAN).format(Date(now)),
            )
            views.setOnClickPendingIntent(R.id.widget_header, appIntent(context))
            views.setOnClickPendingIntent(R.id.widget_empty, appIntent(context))
            views.removeAllViews(R.id.widget_tasks)
            views.setViewVisibility(R.id.widget_empty, if (tasks.isEmpty()) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_tasks, if (tasks.isEmpty()) View.GONE else View.VISIBLE)
            views.setViewVisibility(R.id.widget_footer, if (minHeight >= 200) View.VISIBLE else View.GONE)
            views.setTextViewText(
                R.id.widget_footer,
                if (tasks.isEmpty()) "한걸음에서 할 일을 추가하세요" else "다음 할 일 ${tasks.size}개 · 눌러서 확인",
            )
            views.setOnClickPendingIntent(R.id.widget_footer, appIntent(context))

            tasks.take(capacity).forEachIndexed { index, task ->
                val row = RemoteViews(context.packageName, R.layout.widget_task_row)
                val taskId = task.optString("id")
                val title = task.optString("title")
                val highPriority = task.optInt("priority") == 2
                row.setTextViewText(R.id.widget_task_title, title)
                row.setTextColor(R.id.widget_task_title, if (highPriority) RED else INK)
                row.setTextViewText(R.id.widget_task_due, dueLabel(task, now))
                row.setViewVisibility(R.id.widget_priority, if (highPriority) View.VISIBLE else View.GONE)
                row.setViewVisibility(R.id.widget_task_actions, if (index == 0 && minHeight >= 180) View.VISIBLE else View.GONE)
                row.setTextViewText(
                    R.id.widget_start,
                    if (task.optString("status") == "progressing") "계속하기" else "지금 시작",
                )
                row.setContentDescription(R.id.widget_task_content, "$title, ${dueLabel(task, now)}")
                row.setOnClickPendingIntent(R.id.widget_task_content, taskIntent(context, taskId, "open"))
                row.setOnClickPendingIntent(R.id.widget_start, taskIntent(context, taskId, "start"))
                row.setOnClickPendingIntent(R.id.widget_snooze, taskIntent(context, taskId, "snooze"))
                views.addView(R.id.widget_tasks, row)
            }
            manager.updateAppWidget(id, views)
        }

        private fun readTasks(context: Context): List<JSONObject> = try {
            val shared = context.getSharedPreferences(FLUTTER_PREFERENCES, Context.MODE_PRIVATE)
                .getString(SHARED_SNAPSHOT, null)
            val sharedTasks = shared?.let {
                runCatching { JSONObject(it).getJSONArray("tasks") }.getOrNull()
            }
            val json = sharedTasks ?: JSONArray(
                context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                    .getString(SNAPSHOT, "[]") ?: "[]")
            (0 until json.length()).mapNotNull { json.optJSONObject(it) }
        } catch (_: Exception) {
            emptyList()
        }

        private fun dueLabel(task: JSONObject, now: Long): String {
            val due = task.optLong("due")
            val time = SimpleDateFormat("HH:mm", Locale.KOREAN).format(Date(due))
            if (task.optString("status") == "progressing") return "진행 중 · $time"
            if (due < now) return "미뤄진 할 일 · $time"
            val day = Calendar.getInstance().apply { timeInMillis = due }
            val today = Calendar.getInstance().apply { timeInMillis = now }
            val tomorrow = Calendar.getInstance().apply { timeInMillis = now; add(Calendar.DAY_OF_YEAR, 1) }
            val label = when {
                sameDay(day, today) -> "오늘"
                sameDay(day, tomorrow) -> "내일"
                else -> SimpleDateFormat("M/d(E)", Locale.KOREAN).format(Date(due))
            }
            return "$label $time${if (task.optString("status") == "paused") " · 보류" else ""}"
        }

        private fun sameDay(a: Calendar, b: Calendar): Boolean =
            a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
                a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)

        private fun appIntent(context: Context): PendingIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        private fun taskIntent(context: Context, id: String, actionName: String): PendingIntent {
            val uri = Uri.Builder().scheme("hangeoreum").authority("task")
                .appendQueryParameter("id", id).appendQueryParameter("action", actionName).build()
            return PendingIntent.getActivity(
                context,
                0,
                Intent(Intent.ACTION_VIEW, uri, context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                // The URI identifies each occurrence/action, so PendingIntents never alias.
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
