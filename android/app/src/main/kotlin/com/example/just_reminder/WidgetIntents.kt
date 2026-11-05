package com.example.just_reminder

import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * What a tap on a widget does. The links are read by the app
 * (lib/src/services/app_events.dart `appEventForWidgetUri`) and by Dart in
 * the background (lib/src/background/background_handlers.dart
 * `reminderToMarkDone`); their hosts predate the "Done" wording.
 */
object WidgetIntents {
    fun reminderUri(reminderId: String): Uri =
        Uri.parse("justreminder://reminder/${Uri.encode(reminderId)}?homeWidget")

    fun doneUri(reminderId: String): Uri =
        Uri.parse("justreminder://acknowledge?id=${Uri.encode(reminderId)}")

    /** Keeps the configuration PendingIntents of different widgets apart. */
    fun configureUri(appWidgetId: Int): Uri = Uri.parse("justreminder://configure/$appWidgetId")

    /** Opens [reminderId] in the app. */
    fun open(context: Context, reminderId: String): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, reminderUri(reminderId))

    /** Opens the app. */
    fun openApp(context: Context): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)

    /** Marks [reminderId] done in the background (Dart `widgetInteractionCallback`). */
    fun done(context: Context, reminderId: String): PendingIntent =
        HomeWidgetBackgroundIntent.getBroadcast(context, doneUri(reminderId))

    /** Opens the configuration of widget [appWidgetId] again. */
    fun configure(context: Context, appWidgetId: Int, activity: Class<out Activity>): PendingIntent =
        PendingIntent.getActivity(
            context,
            appWidgetId,
            configureIntent(context, appWidgetId, activity),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    fun configureIntent(context: Context, appWidgetId: Int, activity: Class<out Activity>): Intent =
        Intent(context, activity).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_CONFIGURE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            data = configureUri(appWidgetId)
        }
}
