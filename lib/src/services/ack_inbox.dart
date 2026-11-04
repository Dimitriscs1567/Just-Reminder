import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import 'widget_storage_keys.dart';

/// Mailbox of acknowledgments, readable and writable from any isolate.
///
/// Every acknowledgment — from the app, a widget tap or a notification
/// button — is logged here with its time. The app's sync replays the log
/// into the database, which only the main isolate may touch.
abstract interface class AckInbox {
  /// Logged acknowledgment instants for [reminderId], oldest first.
  Future<List<DateTime>> read(String reminderId);

  /// Logs an acknowledgment of [reminderId] at [at].
  Future<void> add(String reminderId, DateTime at);

  /// Forgets everything logged for [reminderId].
  Future<void> clear(String reminderId);
}

/// [AckInbox] backed by home_widget storage, shared with background
/// isolates and the native widget code.
class HomeWidgetAckInbox implements AckInbox {
  const HomeWidgetAckInbox();

  /// Older entries are dropped; they were applied long ago.
  static const maxEntries = 50;

  @override
  Future<List<DateTime>> read(String reminderId) async => decodeAcknowledgments(
    await HomeWidget.getWidgetData<String>(
      WidgetStorageKeys.acknowledgments(reminderId),
    ),
  );

  @override
  Future<void> add(String reminderId, DateTime at) async {
    final updated = [...await read(reminderId), at]..sort();
    final kept = updated.length > maxEntries
        ? updated.sublist(updated.length - maxEntries)
        : updated;
    await HomeWidget.saveWidgetData<String>(
      WidgetStorageKeys.acknowledgments(reminderId),
      encodeAcknowledgments(kept),
    );
  }

  @override
  Future<void> clear(String reminderId) async {
    await HomeWidget.saveWidgetData<String>(
      WidgetStorageKeys.acknowledgments(reminderId),
      null,
    );
  }
}

/// In-memory [AckInbox] for tests.
class MemoryAckInbox implements AckInbox {
  final _entries = <String, List<DateTime>>{};

  @override
  Future<List<DateTime>> read(String reminderId) async =>
      List.unmodifiable(_entries[reminderId] ?? const <DateTime>[]);

  @override
  Future<void> add(String reminderId, DateTime at) async {
    (_entries[reminderId] ??= []).add(at);
    _entries[reminderId]!.sort();
  }

  @override
  Future<void> clear(String reminderId) async {
    _entries.remove(reminderId);
  }
}

/// Decodes the stored JSON array; anything unreadable counts as empty.
List<DateTime> decodeAcknowledgments(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List<Object?>) return const [];
    return [
      for (final value in decoded)
        if (value is int) DateTime.fromMillisecondsSinceEpoch(value),
    ]..sort();
  } on FormatException {
    return const [];
  }
}

String encodeAcknowledgments(List<DateTime> acknowledgments) => jsonEncode([
  for (final at in acknowledgments) at.millisecondsSinceEpoch,
]);
