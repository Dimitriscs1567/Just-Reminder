package com.example.just_reminder

import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * Runs a tap on a row of the list widget. Rows of a list can't have
 * PendingIntents of their own, so every row tap comes here (through the
 * list's PendingIntent template, see [ReminderListWidgetProvider]) with
 * what to do in its data URI ([WidgetIntents]):
 *
 * - `justreminder://acknowledge?id=…` → mark done in the background,
 *   exactly like the one-reminder widget's thumbs-up;
 * - `justreminder://reminder/<id>?homeWidget` → open the reminder;
 * - `justreminder://configure/<appWidgetId>` → choose the reminders again.
 *
 * It never shows anything (Theme.NoDisplay) and finishes right away.
 */
class WidgetActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = intent?.data
        when (uri?.host) {
            "acknowledge" -> uri.getQueryParameter("id")?.let { reminderId ->
                try {
                    WidgetIntents.done(this, reminderId).send()
                } catch (e: PendingIntent.CanceledException) {
                    // Nothing to do: the next tap creates it again.
                }
            }

            "reminder" -> startActivity(
                Intent(this, MainActivity::class.java)
                    .setAction(HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION)
                    .setData(uri)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )

            "configure" -> {
                val appWidgetId = intent.getIntExtra(
                    AppWidgetManager.EXTRA_APPWIDGET_ID,
                    AppWidgetManager.INVALID_APPWIDGET_ID,
                )
                if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                    startActivity(
                        WidgetIntents.configureIntent(this, appWidgetId, ListWidgetConfigurationActivity::class.java)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                }
            }
        }
        finish()
    }
}
