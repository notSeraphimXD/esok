package com.habib.jadwal

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Paint
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONObject

class TaskWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        TaskWidgetFactory(applicationContext, intent)
}

private class TaskWidgetFactory(
    private val context: Context,
    intent: Intent,
) : RemoteViewsService.RemoteViewsFactory {
    private val appWidgetId = intent.getIntExtra(
        AppWidgetManager.EXTRA_APPWIDGET_ID,
        AppWidgetManager.INVALID_APPWIDGET_ID,
    )
    private var metrics = TaskWidgetProvider.metricsForWidget(context, appWidgetId)
    private var tasks: List<JSONObject> = emptyList()

    override fun onCreate() {
        reload()
    }

    override fun onDataSetChanged() {
        reload()
    }

    private fun reload() {
        metrics = TaskWidgetProvider.metricsForWidget(context, appWidgetId)
        val day = TaskWidgetProvider.selectedDay(context)
        val items = ArrayList<JSONObject>()
        if (day != null) {
            for (index in 0 until day.tasks.length()) {
                day.tasks.optJSONObject(index)?.let { items.add(it) }
            }
        }
        tasks = items
    }

    override fun getCount(): Int = tasks.size

    override fun getViewAt(position: Int): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.task_widget_item)
        val item = tasks.getOrNull(position) ?: return row
        TaskWidgetProvider.applyRow(row, metrics)

        val isDone = item.optBoolean("done", false)
        row.setTextViewText(R.id.task_title, item.optString("title"))
        row.setTextViewText(R.id.task_time, item.optString("time").replace(":", "."))
        if (isDone) {
            row.setTextColor(R.id.task_title, context.getColor(R.color.widget_muted))
            row.setInt(
                R.id.task_title,
                "setPaintFlags",
                Paint.ANTI_ALIAS_FLAG or Paint.STRIKE_THRU_TEXT_FLAG,
            )
            row.setImageViewResource(R.id.task_check, R.drawable.widget_check_on)
        } else {
            row.setTextColor(R.id.task_title, context.getColor(R.color.widget_ink))
            row.setInt(
                R.id.task_title,
                "setPaintFlags",
                Paint.ANTI_ALIAS_FLAG,
            )
            row.setImageViewResource(R.id.task_check, R.drawable.widget_check_off)
        }

        val taskId = item.optString("id")
        val toggleFill = Intent().apply {
            putExtra(
                TaskWidgetActionActivity.EXTRA_ACTION,
                TaskWidgetActionActivity.ACTION_TOGGLE,
            )
            putExtra(TaskToggleReceiver.EXTRA_TASK_ID, taskId)
            putExtra(TaskToggleReceiver.EXTRA_DONE, !isDone)
        }
        row.setOnClickFillInIntent(R.id.task_check, toggleFill)

        val openFill = Intent().apply {
            putExtra(
                TaskWidgetActionActivity.EXTRA_ACTION,
                TaskWidgetActionActivity.ACTION_OPEN,
            )
            putExtra(TaskWidgetActionActivity.EXTRA_URI, "jadwal://task/$taskId")
        }
        row.setOnClickFillInIntent(R.id.task_body, openFill)

        return row
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false

    override fun onDestroy() {}
}
