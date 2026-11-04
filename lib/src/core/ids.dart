import 'dart:math';

final _random = Random.secure();
const _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

/// A new random id made of `[0-9a-z]` only, so it is safe in storage keys
/// and URIs. Prefixed with the creation time, so ids sort by creation.
String newId() {
  final time = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final suffix = List<String>.generate(
    8,
    (_) => _alphabet[_random.nextInt(_alphabet.length)],
  ).join();
  return '$time$suffix';
}
