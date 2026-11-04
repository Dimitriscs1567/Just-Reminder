import 'dart:ui';

/// Formats [value] for path data: at most 3 decimals, no trailing zeros.
String formatNumber(double value) {
  var text = value.toStringAsFixed(3);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return text == '-0' ? '0' : text;
}

/// A vector path of absolute move, line, cubic and close segments, parsed
/// from SVG path data. Supports what Material icon paths use: M, L, H, V,
/// C, S and Z, absolute and relative.
class IconPath {
  IconPath.parse(String data) : _segments = _parse(data);

  const IconPath._(this._segments);

  final List<_Segment> _segments;

  /// This path scaled by [scale], then moved by [dx] and [dy].
  IconPath transform({double scale = 1, double dx = 0, double dy = 0}) =>
      IconPath._([
        for (final segment in _segments)
          segment.map((x, y) => (x * scale + dx, y * scale + dy)),
      ]);

  Path toPath() {
    final path = Path();
    for (final segment in _segments) {
      switch (segment) {
        case _Move(:final x, :final y):
          path.moveTo(x, y);
        case _Line(:final x, :final y):
          path.lineTo(x, y);
        case _Cubic(:final x1, :final y1, :final x2, :final y2, :final x, :final y):
          path.cubicTo(x1, y1, x2, y2, x, y);
        case _Close():
          path.close();
      }
    }
    return path;
  }

  /// Absolute path data for SVG and Android vector drawables.
  String toPathData() => _segments.map((segment) => segment.data).join();
}

typedef _PointMap = (double, double) Function(double x, double y);

String _point(double x, double y) => '${formatNumber(x)},${formatNumber(y)}';

sealed class _Segment {
  const _Segment();

  _Segment map(_PointMap f);

  String get data;
}

final class _Move extends _Segment {
  const _Move(this.x, this.y);

  final double x;
  final double y;

  @override
  _Segment map(_PointMap f) {
    final (mx, my) = f(x, y);
    return _Move(mx, my);
  }

  @override
  String get data => 'M${_point(x, y)}';
}

final class _Line extends _Segment {
  const _Line(this.x, this.y);

  final double x;
  final double y;

  @override
  _Segment map(_PointMap f) {
    final (mx, my) = f(x, y);
    return _Line(mx, my);
  }

  @override
  String get data => 'L${_point(x, y)}';
}

final class _Cubic extends _Segment {
  const _Cubic(this.x1, this.y1, this.x2, this.y2, this.x, this.y);

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double x;
  final double y;

  @override
  _Segment map(_PointMap f) {
    final (mx1, my1) = f(x1, y1);
    final (mx2, my2) = f(x2, y2);
    final (mx, my) = f(x, y);
    return _Cubic(mx1, my1, mx2, my2, mx, my);
  }

  @override
  String get data => 'C${_point(x1, y1)} ${_point(x2, y2)} ${_point(x, y)}';
}

final class _Close extends _Segment {
  const _Close();

  @override
  _Segment map(_PointMap f) => this;

  @override
  String get data => 'Z';
}

final _token = RegExp(
  r'[MmLlHhVvCcSsZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
);
final _command = RegExp(r'^[A-Za-z]$');

List<_Segment> _parse(String data) {
  final tokens = [for (final match in _token.allMatches(data)) match[0]!];
  final segments = <_Segment>[];
  var index = 0;
  var command = '';
  var x = 0.0;
  var y = 0.0;
  var startX = 0.0;
  var startY = 0.0;
  // Second control point of the previous cubic, for S.
  (double, double)? lastControl;
  double number() => double.parse(tokens[index++]);

  while (index < tokens.length) {
    if (_command.hasMatch(tokens[index])) {
      command = tokens[index++];
    } else if (command.isEmpty || command.toUpperCase() == 'Z') {
      throw FormatException('Number without a command in "$data"');
    }
    final relative = command.toLowerCase() == command;
    final baseX = relative ? x : 0.0;
    final baseY = relative ? y : 0.0;
    (double, double)? control;
    switch (command.toUpperCase()) {
      case 'M':
        x = baseX + number();
        y = baseY + number();
        startX = x;
        startY = y;
        segments.add(_Move(x, y));
        // Further coordinate pairs are lines.
        command = relative ? 'l' : 'L';
      case 'L':
        x = baseX + number();
        y = baseY + number();
        segments.add(_Line(x, y));
      case 'H':
        x = baseX + number();
        segments.add(_Line(x, y));
      case 'V':
        y = baseY + number();
        segments.add(_Line(x, y));
      case 'C':
        final x1 = baseX + number();
        final y1 = baseY + number();
        final x2 = baseX + number();
        final y2 = baseY + number();
        x = baseX + number();
        y = baseY + number();
        segments.add(_Cubic(x1, y1, x2, y2, x, y));
        control = (x2, y2);
      case 'S':
        final (px, py) = lastControl ?? (x, y);
        final x1 = 2 * x - px;
        final y1 = 2 * y - py;
        final x2 = baseX + number();
        final y2 = baseY + number();
        x = baseX + number();
        y = baseY + number();
        segments.add(_Cubic(x1, y1, x2, y2, x, y));
        control = (x2, y2);
      case 'Z':
        segments.add(const _Close());
        x = startX;
        y = startY;
      default:
        throw FormatException('Unsupported path command "$command"');
    }
    lastControl = control;
  }
  return segments;
}
