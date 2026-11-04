import 'dart:convert';

/// 32-bit FNV-1a hash of the UTF-8 bytes of [value].
///
/// Unlike [Object.hashCode] this is stable across runs, isolates, platforms
/// and SDK versions, so it can seed random activation times and derive ids
/// that must stay the same (e.g. notification ids).
int stableHash32(String value) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// [stableHash32] reduced to a non-negative 31-bit int.
int stableHash31(String value) => stableHash32(value) & 0x7FFFFFFF;
