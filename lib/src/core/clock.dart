/// Source of the current time. Injected everywhere "now" matters, so tests
/// can control time.
typedef Clock = DateTime Function();

/// The real clock.
DateTime systemClock() => DateTime.now();
