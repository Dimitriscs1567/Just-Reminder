package com.example.just_reminder

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home screen widget for one reminder: its display name and a green thumbs
 * up, or a red thumbs down (plus the missed count) while an activation waits
 * for acknowledgment. Tapping the thumbs down acknowledges it in the
 * background; tapping elsewhere opens the reminder in the app.
 *
 * 1×1 by default and resizable, with two layouts (see [Layout]). Android 12+
 * switches between them by itself when the widget is resized; older versions
 * get a redraw in [onAppWidgetOptionsChanged].
 *
 * The state is computed from the stored snapshot at render time, and the
 * app schedules redraws at every upcoming activation
 * (HomeWidget.scheduleWidgetUpdates), so the widget flips to thumbs down on
 * time even when the app is not running.
 */
class ReminderWidgetProvider : HomeWidgetProvider() {

    /** The widget's layouts and the smallest size (dp) each one is used at. */
    private enum class Layout(val resource: Int, val minWidth: Float, val minHeight: Float) {
        /** Thumb with a missed-count bubble above the display name. */
        COMPACT(R.layout.reminder_widget_small, 0f, 0f),

        /** Display name, larger thumb, "N missed" (about 2×2 and up). */
        LARGE(R.layout.reminder_widget, 120f, 160f);

        companion object {
            fun forSize(width: Int, height: Int): Layout =
                if (width >= LARGE.minWidth && height >= LARGE.minHeight) LARGE else COMPACT
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val now = System.currentTimeMillis()
        for (appWidgetId in appWidgetIds) {
            update(context, appWidgetManager, appWidgetId, widgetData, now)
        }
    }

    /** Called after a resize. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        update(
            context,
            appWidgetManager,
            appWidgetId,
            HomeWidgetPlugin.getData(context),
            System.currentTimeMillis(),
        )
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val editor = HomeWidgetPlugin.getData(context).edit()
        for (appWidgetId in appWidgetIds) {
            editor.remove(WidgetStore.widgetReminderKey(appWidgetId))
        }
        editor.apply()
        super.onDeleted(context, appWidgetIds)
    }

    private fun update(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        widgetData: SharedPreferences,
        now: Long,
    ) {
        val state = WidgetStore.stateFor(widgetData, appWidgetId, now)
        fun views(layout: Layout) = render(context, appWidgetId, state, layout)

        val remoteViews = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // The launcher shows the largest layout that fits, for every size
            // the widget takes (portrait, landscape, after resizing).
            RemoteViews(Layout.entries.associate { SizeF(it.minWidth, it.minHeight) to views(it) })
        } else {
            // Portrait is min width × max height, landscape max width × min height.
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val portrait = Layout.forSize(
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH),
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT),
            )
            val landscape = Layout.forSize(
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH),
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT),
            )
            if (portrait == landscape) views(portrait) else RemoteViews(views(landscape), views(portrait))
        }
        appWidgetManager.updateAppWidget(appWidgetId, remoteViews)
    }

    private fun render(
        context: Context,
        appWidgetId: Int,
        state: WidgetStore.State,
        layout: Layout,
    ): RemoteViews {
        val compact = layout == Layout.COMPACT
        val views = RemoteViews(context.packageName, layout.resource)
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
                views.setViewVisibility(R.id.widget_thumb_group, View.VISIBLE)
                views.setViewVisibility(R.id.widget_label, View.GONE)
                views.setImageViewResource(
                    R.id.widget_thumb,
                    if (waiting) R.drawable.widget_thumb_down else R.drawable.widget_thumb_up,
                )
                views.setContentDescription(
                    R.id.widget_thumb,
                    context.getString(if (waiting) R.string.widget_acknowledge else R.string.widget_all_clear),
                )
                if (waiting && state.missed > 0) {
                    val missed = context.getString(R.string.widget_missed, state.missed)
                    views.setViewVisibility(R.id.widget_badge, View.VISIBLE)
                    // The compact bubble only has room for the number.
                    views.setTextViewText(R.id.widget_badge, if (compact) countLabel(state.missed) else missed)
                    views.setContentDescription(R.id.widget_badge, missed)
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
                views.setViewVisibility(R.id.widget_thumb_group, View.GONE)
                views.setViewVisibility(R.id.widget_badge, View.GONE)
                views.setViewVisibility(R.id.widget_label, View.VISIBLE)
                val (compactLabel, fullLabel) = when (state.kind) {
                    WidgetStore.Kind.ARCHIVED -> R.string.widget_archived_short to R.string.widget_archived
                    WidgetStore.Kind.DELETED -> R.string.widget_deleted_short to R.string.widget_deleted
                    else -> R.string.widget_choose_short to R.string.widget_choose
                }
                views.setTextViewText(R.id.widget_label, context.getString(if (compact) compactLabel else fullLabel))
                views.setContentDescription(R.id.widget_label, context.getString(fullLabel))
                views.setOnClickPendingIntent(R.id.widget_root, configureIntent(context, appWidgetId))
            }
        }
        return views
    }

    private fun countLabel(missed: Int): String = if (missed > 99) "99+" else missed.toString()

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
