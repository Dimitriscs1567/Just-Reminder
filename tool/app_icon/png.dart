import 'dart:io';
import 'dart:typed_data';

/// Encodes straight (not premultiplied) RGBA pixels as a PNG. Without
/// [alpha] the alpha channel is dropped (an RGB PNG): the App Store rejects
/// app icons that have one, even a fully opaque one.
Uint8List encodePng(
  Uint8List rgba,
  int width,
  int height, {
  required bool alpha,
}) {
  final channels = alpha ? 4 : 3;
  final stride = 1 + width * channels;
  final raw = Uint8List(height * stride);
  for (var row = 0; row < height; row++) {
    // The first byte of every row is its filter type: 0 = none.
    var out = row * stride + 1;
    for (var column = 0; column < width; column++) {
      final pixel = (row * width + column) * 4;
      raw[out++] = rgba[pixel];
      raw[out++] = rgba[pixel + 1];
      raw[out++] = rgba[pixel + 2];
      if (alpha) raw[out++] = rgba[pixel + 3];
    }
  }
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bits per channel
    ..setUint8(9, alpha ? 6 : 2); // RGBA or RGB; no compression options
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    ..._chunk('IHDR', header.buffer.asUint8List()),
    ..._chunk('IDAT', ZLibEncoder(level: 9).convert(raw)),
    ..._chunk('IEND', const []),
  ]);
}

List<int> _chunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32(body));
  return [
    ...length.buffer.asUint8List(),
    ...body,
    ...crc.buffer.asUint8List(),
  ];
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) == 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >>> 8);
  }
  return crc ^ 0xFFFFFFFF;
}
