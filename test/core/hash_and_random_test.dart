import 'package:flutter_test/flutter_test.dart';
import 'package:just_reminder/src/core/seeded_random.dart';
import 'package:just_reminder/src/core/stable_hash.dart';

void main() {
  group('stableHash32', () {
    test('matches the FNV-1a reference values', () {
      expect(stableHash32(''), 0x811c9dc5);
      expect(stableHash32('a'), 0xe40c292c);
      expect(stableHash32('foobar'), 0xbf9cf968);
    });

    test('stableHash31 is a non-negative 31-bit value', () {
      for (final value in ['', 'a', 'reminder@1767225600000', 'ünïcødé']) {
        final hash = stableHash31(value);
        expect(hash, greaterThanOrEqualTo(0));
        expect(hash, lessThanOrEqualTo(0x7FFFFFFF));
      }
    });
  });

  group('SeededRandom', () {
    List<double> sequence(int seed) {
      final random = SeededRandom(seed);
      return List<double>.generate(20, (_) => random.nextDouble());
    }

    test('repeats the same sequence for the same seed', () {
      expect(sequence(42), sequence(42));
    });

    test('gives different sequences for different seeds', () {
      expect(sequence(1), isNot(sequence(2)));
    });

    test('stays in range and covers every bucket', () {
      final random = SeededRandom(7);
      final seen = <int>{};
      for (var i = 0; i < 1000; i++) {
        final value = random.nextDouble();
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThan(1));
        seen.add(random.nextInt(7));
      }
      expect(seen, {0, 1, 2, 3, 4, 5, 6});
    });

    test('is pinned: changing the algorithm would move saved random times', () {
      final random = SeededRandom(stableHash32('reminder|2026-11-04'));
      final first = [for (var i = 0; i < 3; i++) random.nextInt(1000000)];
      expect(first, _pinnedFirstValues);
    });
  });
}

/// Cross-checked against the reference JavaScript mulberry32 + FNV-1a.
const _pinnedFirstValues = <int>[539299, 35683, 543396];
