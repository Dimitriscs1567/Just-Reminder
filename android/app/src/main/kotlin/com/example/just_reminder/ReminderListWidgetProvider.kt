package com.example.just_reminder

import android.app.ActivityOptions
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import androidx.core.widget.RemoteViewsCompat
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home screen widget listing several reminders, in the order the user
 * picked them (ListWidgetConfigurationActivity → `jr.listwidget.<id>`).
 * One row per reminder: state icon, display name and status ("Due · 1
 * missed", "Missed · 2", "Done", …), the due one on a teal background. The
 * list scrolls when the rows don't fit.
 *
 * Taps: the teal ring marks that reminder done (in the background), the
 * row opens it in the app, an archived or deleted row opens the
 * configuration again, the header opens the app. Rows of a list can't have
 * PendingIntents of their own, so their taps go through one template to
 * [WidgetActionActivity] with what to do in the data URI.
 *
 * Like [ReminderWidgetProvider], the rows are computed at render time and
 * the app schedules redraws at every change.
 */
class ReminderListWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val now = System.currentTimeMillis()
        for (appWidgetId in appWidgetIds) {
            val views = render(context, appWidgetId, widgetData, now)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val editor = HomeWidgetPlugin.getData(context).edit()
        for (appWidgetId in appWidgetIds) {
            editor.remove(WidgetStore.listWidgetKey(appWidgetId))
        }
        editor.apply()
        super.onDeleted(context, appWidgetIds)
    }

    private fun render(
        context: Context,
        appWidgetId: Int,
        widgetData: SharedPreferences,
        now: Long,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.reminder_list_widget)
        val reminderIds = WidgetStore.listFor(widgetData, appWidgetId).orEmpty()

        views.setOnClickPendingIntent(R.id.list_header, WidgetIntents.openApp(context))
        views.setOnClickPendingIntent(
            R.id.list_empty,
            WidgetIntents.configure(context, appWidgetId, ListWidgetConfigurationActivity::class.java),
        )
        views.setViewVisibility(R.id.list_empty, if (reminderIds.isEmpty()) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.list_rows, if (reminderIds.isEmpty()) View.GONE else View.VISIBLE)
        views.setPendingIntentTemplate(R.id.list_rows, rowTapTemplate(context, appWidgetId))

        val items = RemoteViewsCompat.RemoteCollectionItems.Builder()
            .setHasStableIds(true)
            .setViewTypeCount(1)
        reminderIds.forEachIndexed { index, reminderId ->
            val state = WidgetStore.reminderState(widgetData, reminderId, now)
            items.addItem(index.toLong(), row(context, appWidgetId, state))
        }
        RemoteViewsCompat.setRemoteAdapter(context, views, appWidgetId, R.id.list_rows, items.build())
        return views
    }

    private fun row(context: Context, appWidgetId: Int, state: WidgetStore.State): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.reminder_list_row)
        val firing = state.kind == WidgetStore.Kind.FIRING
        val gone = state.kind == WidgetStore.Kind.ARCHIVED || state.kind == WidgetStore.Kind.DELETED
        val reminderId = state.reminderId.orEmpty()

        row.setInt(R.id.row_root, "setBackgroundResource", if (firing) R.drawable.widget_row_firing else 0)
        row.setTextViewText(R.id.row_name, state.displayName)
        row.setTextColorResource(
            context,
            R.id.row_name,
            when {
                firing -> R.color.widget_on_firing
                gone -> R.color.widget_neutral_variant
                else -> R.color.widget_on_neutral
            },
        )
        row.setTextViewText(R.id.row_status, WidgetLook.status(context, state))
        row.setTextColorResource(
            context,
            R.id.row_status,
            if (firing) R.color.widget_on_firing_variant else R.color.widget_neutral_variant,
        )

        val icon = WidgetLook.icon(state.kind, inList = true)
        if (icon != null) {
            row.setViewVisibility(R.id.row_icon, View.VISIBLE)
            row.setImageViewResource(R.id.row_icon, icon)
            row.setContentDescription(R.id.row_icon, context.getString(WidgetLook.iconDescription(state.kind)))
        } else {
            // Keeps the names lined up.
            row.setViewVisibility(R.id.row_icon, View.INVISIBLE)
        }

        val open = if (gone) {
            WidgetIntents.configureUri(appWidgetId)
        } else {
            WidgetIntents.reminderUri(reminderId)
        }
        row.setOnClickFillInIntent(R.id.row_root, Intent().setData(open))
        row.setOnClickFillInIntent(
            R.id.row_icon,
            Intent().setData(if (firing) WidgetIntents.doneUri(reminderId) else open),
        )
        return row
    }

    /**
     * Where row taps go; each row fills in its URI. Mutable so the fill-in
     * can set the data; explicit, so nothing else can receive it.
     */
    private fun rowTapTemplate(context: Context, appWidgetId: Int): PendingIntent {
        val intent = Intent(context, WidgetActionActivity::class.java)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_MUTABLE
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return PendingIntent.getActivity(context, appWidgetId, intent, flags)
        }
        // Like home_widget's launch intents: the activity may start the app.
        val options = ActivityOptions.makeBasic()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            options.setPendingIntentCreatorBackgroundActivityStartMode(
                ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
            )
        } else {
            options.pendingIntentBackgroundActivityStartMode = ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
        }
        return PendingIntent.getActivity(context, appWidgetId, intent, flags, options.toBundle())
    }
}
