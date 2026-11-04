/// Keys in the home_widget storage (Android SharedPreferences
/// `HomeWidgetPreferences`, iOS App Group UserDefaults).
///
/// Native widget code (Kotlin / Swift) reads the same keys, so change them on
/// all sides together.
abstract final class WidgetStorageKeys {
  /// JSON array of acknowledgment instants (epoch ms) for a reminder.
  ///
  /// Appended by whoever acknowledges — the app, a widget tap, or the
  /// notification's Acknowledge button (the last two run in background
  /// isolates that must not open the database). The app's sync applies the
  /// entries to the database.
  static String acknowledgments(String reminderId) => 'jr.acks.$reminderId';
}
