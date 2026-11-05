package com.example.just_reminder

import io.flutter.embedding.android.FlutterActivity

/**
 * Opened by the launcher when a list widget is added or set up again (and
 * by tapping its archived or deleted rows). Runs the Flutter entry point
 * `listWidgetConfigurationMain` from lib/main.dart: the user ticks the
 * reminders to show and orders them; it finishes via home_widget.
 */
class ListWidgetConfigurationActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "listWidgetConfigurationMain"
}
