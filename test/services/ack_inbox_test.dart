import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/services/ack_inbox.dart';

void main() {
  test('encodes and decodes acknowledgment logs', () {
    final times = [DateTime(2026, 11, 4, 9, 30), DateTime(2026, 11, 4, 10, 2)];
    expect(decodeAcknowledgments(encodeAcknowledgments(times)), times);
  });

  test('unreadable logs count as empty', () {
    expect(decodeAcknowledgments(null), isEmpty);
    expect(decodeAcknowledgments(''), isEmpty);
    expect(decodeAcknowledgments('not json'), isEmpty);
    expect(decodeAcknowledgments('{"a": 1}'), isEmpty);
  });

  test('decoding sorts and skips non-numbers', () {
    expect(decodeAcknowledgments('[300, "x", 100]'), [
      DateTime.fromMillisecondsSinceEpoch(100),
      DateTime.fromMillisecondsSinceEpoch(300),
    ]);
  });
}
