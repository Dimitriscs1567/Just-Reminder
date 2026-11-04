/// Small deterministic pseudo-random generator (mulberry32).
///
/// `dart:math`'s `Random(seed)` does not promise the same sequence across
/// SDK releases. Random activation times must never move once shown, so the
/// app uses this generator, whose output depends only on the seed.
class SeededRandom {
  SeededRandom(int seed) : _state = seed & _mask;

  static const _mask = 0xFFFFFFFF;

  int _state;

  /// The next value in `[0, 1)`.
  double nextDouble() {
    _state = (_state + 0x6D2B79F5) & _mask;
    var t = _state;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= (t + _imul(t ^ (t >> 7), t | 61)) & _mask;
    return ((t ^ (t >> 14)) & _mask) / 4294967296;
  }

  /// The next int in `[0, max)`; [max] must be positive.
  int nextInt(int max) {
    assert(max > 0, 'max must be positive');
    return (nextDouble() * max).floor();
  }

  /// 32-bit multiplication with wrap-around (like JavaScript's Math.imul).
  static int _imul(int a, int b) => (a * b) & _mask;
}
