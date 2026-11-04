import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'app_icon.dart';
import 'png.dart';

/// Writes every app icon file from app_icon.dart. Run from the project root:
///
///     flutter test tool/app_icon/generate_app_icon_test.dart
///
/// It is a test only so that dart:ui can render without a device; the
/// normal `flutter test` run (test/) does not include it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generates the Android and iOS app icons', () async {
    const res = 'android/app/src/main/res';
    _writeText('$res/drawable/ic_launcher_background.xml', androidBackground());
    _writeText('$res/drawable/ic_launcher_foreground.xml', androidForeground());
    _writeText('$res/drawable/ic_launcher_monochrome.xml', androidMonochrome());
    _writeText('$res/mipmap-anydpi-v26/ic_launcher.xml', androidAdaptiveIcon);
    // Android 7 launchers have no adaptive icons.
    const legacySizes = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    for (final MapEntry(key: density, value: size) in legacySizes.entries) {
      await _writePng(
        '$res/mipmap-$density/ic_launcher.png',
        size,
        IconStyle.full,
        alpha: true,
        circle: true,
      );
    }

    const iosSet = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    // Other images (e.g. Flutter's template sizes) would be unassigned.
    for (final file in Directory(iosSet).listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (name.endsWith('.png') && !iosIconFiles.containsKey(name)) {
        file.deleteSync();
      }
    }
    for (final MapEntry(key: name, value: style) in iosIconFiles.entries) {
      // The light icon must be opaque and have no alpha channel.
      await _writePng(
        '$iosSet/$name',
        1024,
        style,
        alpha: style != IconStyle.full,
      );
    }
    _writeText(
      '$iosSet/Contents.json',
      '${const JsonEncoder.withIndent('  ').convert(iosContents())}\n',
    );
  });
}

Future<void> _writePng(
  String path,
  int size,
  IconStyle style, {
  required bool alpha,
  bool circle = false,
}) async {
  final image = await renderIcon(size: size, style: style, circle: circle);
  final pixels = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(
      encodePng(pixels!.buffer.asUint8List(), size, size, alpha: alpha),
    );
}

void _writeText(String path, String text) => File(path)
  ..createSync(recursive: true)
  ..writeAsStringSync(text);
