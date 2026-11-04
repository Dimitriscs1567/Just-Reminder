package com.example.just_reminder

import io.flutter.embedding.android.FlutterActivity

/**
 * Opened by the launcher when a reminder widget is added (and by tapping a
 * widget whose reminder is gone). Runs the Flutter entry point
 * `widgetConfigurationMain` from lib/main.dart, which lists the reminders
 * and finishes the configuration via home_widget.
 */
class WidgetConfigurationActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "widgetConfigurationMain"
}
