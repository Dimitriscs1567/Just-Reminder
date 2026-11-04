import 'dart:async';

/// Something the outside world asks the app to do: open a reminder (tap on
/// a notification or widget), acknowledge one (notification button while
/// the app runs), or explain how to re-pick an iOS widget's reminder.
sealed class AppEvent {
  const AppEvent();
}

final class OpenReminder extends AppEvent {
  const OpenReminder(this.reminderId);

  final String reminderId;
}

final class AcknowledgeReminder extends AppEvent {
  const AcknowledgeReminder(this.reminderId);

  final String reminderId;
}

/// The iOS widget of an archived or deleted reminder was tapped.
final class ExplainWidgetEditing extends AppEvent {
  const ExplainWidgetEditing();
}

/// Delivers [AppEvent]s from plugin callbacks (set up in `main`) to the UI.
class AppEvents {
  final _controller = StreamController<AppEvent>.broadcast();
  AppEvent? _launch;

  Stream<AppEvent> get stream => _controller.stream;

  void add(AppEvent event) => _controller.add(event);

  /// The event that launched the app, if any; handled once.
  set launchEvent(AppEvent? event) => _launch = event;

  AppEvent? takeLaunchEvent() {
    final event = _launch;
    _launch = null;
    return event;
  }

  Future<void> dispose() => _controller.close();
}

/// Maps a widget URL to an event:
/// - `justreminder://reminder/<id>` → [OpenReminder]
/// - `justreminder://widget-help` → [ExplainWidgetEditing]
AppEvent? appEventForWidgetUri(Uri? uri) {
  if (uri == null) return null;
  return switch (uri.host) {
    'reminder' when uri.pathSegments.isNotEmpty => OpenReminder(
      uri.pathSegments.first,
    ),
    'widget-help' => const ExplainWidgetEditing(),
    _ => null,
  };
}
