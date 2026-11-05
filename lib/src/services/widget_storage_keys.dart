/// Keys in the home_widget storage (Android SharedPreferences
/// `HomeWidgetPreferences`, iOS App Group UserDefaults).
///
/// The native widget code reads the same keys —
/// `android/app/src/main/kotlin/com/example/just_reminder/WidgetStore.kt`
/// and `ios/ReminderWidget/WidgetStore.swift` — so change them on all sides
/// together.
abstract final class WidgetStorageKeys {
  /// JSON array of the instants (epoch ms) a reminder was marked done (the
  /// "ack" log; the name predates the Done wording).
  ///
  /// Appended by whatever marks it done — the app, a widget tap, or the
  /// notification's Done button (the last two run in background isolates
  /// or the widget extension, which must not open the database). The app's
  /// sync applies the entries to the database.
  static String acknowledgments(String reminderId) => 'jr.acks.$reminderId';

  /// JSON snapshot a widget renders a reminder from (see
  /// `widget_snapshot.dart`). Deleted reminders keep a small tombstone so
  /// their widgets can say "Deleted".
  static String snapshot(String reminderId) => 'jr.reminder.$reminderId';

  /// JSON array of `{id, name, displayName, archived}` for every reminder
  /// (not deleted ones). Widget configuration lists the non-archived ones.
  static const index = 'jr.reminders';

  /// Android only: the reminder id an app widget instance shows.
  static String androidWidget(int appWidgetId) => 'jr.widget.$appWidgetId';
}
