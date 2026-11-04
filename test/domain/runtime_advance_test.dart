import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/domain/activation.dart';
import 'package:just_reminder/src/domain/reminder_runtime.dart';
import 'package:just_reminder/src/domain/runtime_advance.dart';

final start = DateTime(2026, 11, 4, 8);
DateTime at(int hour, [int minute = 0]) => DateTime(2026, 11, 4, hour, minute);

ReminderRuntime fresh() => ReminderRuntime.initial('r', start);

ActivationRecord record(
  DateTime scheduledAt,
  ActivationStatus status, [
  DateTime? acknowledgedAt,
]) => ActivationRecord(
  reminderId: 'r',
  scheduledAt: scheduledAt,
  status: status,
  acknowledgedAt: acknowledgedAt,
);

void main() {
  test('an activation becomes the waiting one', () {
    final result = advanceRuntime(
      runtime: fresh(),
      activations: [at(9)],
      acknowledgments: const [],
      until: at(9, 5),
    );
    expect(result.runtime.pendingAt, at(9));
    expect(result.runtime.isActive, isTrue);
    expect(result.runtime.processedUntil, at(9, 5));
    expect(result.records, [record(at(9), ActivationStatus.pending)]);
  });

  test('a new activation marks the waiting one missed', () {
    final result = advanceRuntime(
      runtime: fresh(),
      activations: [at(9), at(10)],
      acknowledgments: const [],
      until: at(10, 5),
    );
    expect(result.runtime.pendingAt, at(10));
    expect(result.runtime.missedCount, 1);
    expect(
      result.records,
      unorderedEquals([
        record(at(9), ActivationStatus.missed),
        record(at(10), ActivationStatus.pending),
      ]),
    );
  });

  test('an acknowledgment clears it and resets the missed count', () {
    final waiting = fresh().copyWith(pendingAt: at(10), missedCount: 2);
    final result = advanceRuntime(
      runtime: waiting,
      activations: const [],
      acknowledgments: [at(10, 20)],
      until: at(10, 30),
    );
    expect(result.runtime.isActive, isFalse);
    expect(result.runtime.missedCount, 0);
    expect(result.runtime.lastAcknowledgedAt, at(10, 20));
    expect(result.runtime.appliedAckUntil, at(10, 20));
    expect(result.records, [
      record(at(10), ActivationStatus.acknowledged, at(10, 20)),
    ]);
  });

  test('events are replayed in time order', () {
    final result = advanceRuntime(
      runtime: fresh(),
      activations: [at(9), at(10), at(11)],
      acknowledgments: [at(9, 30)],
      until: at(11, 5),
    );
    expect(
      result.records,
      unorderedEquals([
        record(at(9), ActivationStatus.acknowledged, at(9, 30)),
        record(at(10), ActivationStatus.missed),
        record(at(11), ActivationStatus.pending),
      ]),
    );
    expect(result.runtime.missedCount, 1);
  });

  test('an acknowledgment with nothing waiting changes no history', () {
    final result = advanceRuntime(
      runtime: fresh(),
      activations: const [],
      acknowledgments: [at(9)],
      until: at(9, 1),
    );
    expect(result.records, isEmpty);
    expect(result.runtime.appliedAckUntil, at(9));
    expect(result.runtime.lastAcknowledgedAt, isNull);
  });

  test('on a tie the activation comes before the acknowledgment', () {
    final result = advanceRuntime(
      runtime: fresh(),
      activations: [at(9)],
      acknowledgments: [at(9)],
      until: at(9),
    );
    expect(result.records, [
      record(at(9), ActivationStatus.acknowledged, at(9)),
    ]);
  });

  test('closePendingAsMissed records the waiting activation as missed', () {
    final closed = closePendingAsMissed(fresh().copyWith(pendingAt: at(9)));
    expect(closed.runtime.isActive, isFalse);
    expect(closed.runtime.missedCount, 1);
    expect(closed.records, [record(at(9), ActivationStatus.missed)]);

    expect(closePendingAsMissed(fresh()).records, isEmpty);
  });
}
