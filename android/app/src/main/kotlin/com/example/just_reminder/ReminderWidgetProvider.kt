package com.example.just_reminder

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home screen widget for one reminder: its display name and a green thumbs
 * up, or a red thumbs down (plus "N missed") while an activation waits for
 * acknowledgment. Tapping the thumbs down acknowledges it in the background;
 * tapping elsewhere opens the reminder in the app.
 *
 * The state is computed from the stored snapshot at render time, and the
 * app schedules redraws at every upcoming activation
 * (HomeWidget.scheduleWidgetUpdates), so the widget flips to thumbs down on
 * time even when the app is not running.
 */
class ReminderWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val now = System.currentTimeMillis()
        for (appWidgetId in appWidgetIds) {
            val state = WidgetStore.stateFor(widgetData, appWidgetId, now)
            appWidgetManager.updateAppWidget(appWidgetId, render(context, appWidgetId, state))
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val editor = HomeWidgetPlugin.getData(context).edit()
        for (appWidgetId in appWidgetIds) {
            editor.remove(WidgetStore.widgetReminderKey(appWidgetId))
        }
        editor.apply()
        super.onDeleted(context, appWidgetIds)
    }

    private fun render(context: Context, appWidgetId: Int, state: WidgetStore.State): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.reminder_widget)
        val (background, foreground) = when (state.kind) {
            WidgetStore.Kind.WAITING -> R.drawable.widget_background_waiting to R.color.widget_on_waiting
            WidgetStore.Kind.CLEAR -> R.drawable.widget_background_clear to R.color.widget_on_clear
            else -> R.drawable.widget_background_neutral to R.color.widget_on_neutral
        }
        views.setInt(R.id.widget_root, "setBackgroundResource", background)
        val textColor = context.getColor(foreground)
        views.setTextColor(R.id.widget_title, textColor)
        views.setTextColor(R.id.widget_label, textColor)
        views.setTextViewText(
            R.id.widget_title,
            state.displayName.ifEmpty { context.getString(R.string.widget_default_title) },
        )

        when (state.kind) {
            WidgetStore.Kind.WAITING, WidgetStore.Kind.CLEAR -> {
                val waiting = state.kind == WidgetStore.Kind.WAITING
                views.setViewVisibility(R.id.widget_thumb, View.VISIBLE)
                views.setViewVisibility(R.id.widget_label, View.GONE)
                views.setInt(
                    R.id.widget_thumb,
                    "setBackgroundResource",
                    if (waiting) R.drawable.widget_circle_negative else R.drawable.widget_circle_positive,
                )
                views.setImageViewResource(
                    R.id.widget_thumb,
                    if (waiting) R.drawable.ic_widget_thumb_down else R.drawable.ic_widget_thumb_up,
                )
                views.setContentDescription(
                    R.id.widget_thumb,
                    context.getString(if (waiting) R.string.widget_acknowledge else R.string.widget_all_clear),
                )
                if (waiting && state.missed > 0) {
                    views.setViewVisibility(R.id.widget_badge, View.VISIBLE)
                    views.setTextViewText(R.id.widget_badge, context.getString(R.string.widget_missed, state.missed))
                } else {
                    views.setViewVisibility(R.id.widget_badge, View.GONE)
                }

                val open = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("justreminder://reminder/${state.reminderId}?homeWidget"),
                )
                views.setOnClickPendingIntent(R.id.widget_root, open)
                views.setOnClickPendingIntent(
                    R.id.widget_thumb,
                    if (waiting) {
                        HomeWidgetBackgroundIntent.getBroadcast(
                            context,
                            Uri.parse("justreminder://acknowledge?id=${state.reminderId}"),
                        )
                    } else {
                        open
                    },
                )
            }

            else -> {
                // Archived, deleted or not set up yet: tap to pick a reminder.
                views.setViewVisibility(R.id.widget_thumb, View.GONE)
                views.setViewVisibility(R.id.widget_badge, View.GONE)
                views.setViewVisibility(R.id.widget_label, View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_label,
                    context.getString(
                        when (state.kind) {
                            WidgetStore.Kind.ARCHIVED -> R.string.widget_archived
                            WidgetStore.Kind.DELETED -> R.string.widget_deleted
                            else -> R.string.widget_choose
                        },
                    ),
                )
                views.setOnClickPendingIntent(R.id.widget_root, configureIntent(context, appWidgetId))
            }
        }
        return views
    }

    /** Re-opens the widget configuration for [appWidgetId]. */
    private fun configureIntent(context: Context, appWidgetId: Int): PendingIntent {
        val intent = Intent(context, WidgetConfigurationActivity::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_CONFIGURE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            // Keeps the PendingIntents of different widgets apart.
            data = Uri.parse("justreminder://configure/$appWidgetId")
        }
        return PendingIntent.getActivity(
            context,
            appWidgetId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
