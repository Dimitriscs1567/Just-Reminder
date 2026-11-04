import 'dart:ui';

import 'icon_path.dart';

/// The app icon — a white bell with a green thumbs-up badge on teal (chosen
/// 2026-11-05) — drawn on a 96-unit tile. generate_app_icon_test.dart turns
/// it into every file the platforms need.
abstract final class AppIcon {
  static const tile = 96.0;

  static const tealLight = Color(0xFF2DD4BF);
  static const tealDark = Color(0xFF0F766E);

  /// The app's positive green.
  static const green = Color(0xFF1E8E3E);
  static const white = Color(0xFFFFFFFF);

  /// Badge colour in the tinted (grayscale) iOS icon.
  static const tintedGray = Color(0xFF8E8E8E);

  // The design was sketched with the bell near the centre and the badge
  // hanging off its lower right. Bell and badge together are centred on the
  // tile and enlarged a little: _anchor is the middle of the sketch.
  static const _anchor = Offset(56.25, 54.25);
  static const _zoom = 1.1;

  static IconPath _place(IconPath glyph, double scale, Offset offset) =>
      glyph.transform(
        scale: scale * _zoom,
        dx: (offset.dx - _anchor.dx) * _zoom + tile / 2,
        dy: (offset.dy - _anchor.dy) * _zoom + tile / 2,
      );

  /// Material icon "notifications" (Apache 2.0), 24 units, sketched at
  /// twice that size.
  static final bell = _place(
    IconPath.parse(
      'M12,22c1.1,0 2,-0.9 2,-2h-4c0,1.1 0.89,2 2,2zM18,16v-5c0,-3.07 '
      '-1.64,-5.64 -4.5,-6.32V4c0,-0.83 -0.67,-1.5 -1.5,-1.5s-1.5,0.67 '
      '-1.5,1.5v0.68C7.63,5.36 6,7.92 6,11v5l-2,2v1h16v-1l-2,-2z',
    ),
    2,
    const Offset(22, 22),
  );

  /// Material icon "thumb_up" (Apache 2.0), centred in the badge.
  static final thumb = _place(
    IconPath.parse(
      'M1,21h4V9H1v12zM23,10c0,-1.1 -0.9,-2 -2,-2h-6.31l0.95,-4.57 '
      '0.03,-0.32c0,-0.41 -0.17,-0.79 -0.44,-1.06L14.17,1 7.59,7.59'
      'C7.22,7.95 7,8.45 7,9v10c0,1.1 0.9,2 2,2h9c0.83,0 1.54,-0.5 '
      '1.84,-1.22l3.02,-7.05c0.09,-0.23 0.14,-0.47 0.14,-0.73v-2z',
    ),
    0.65,
    const Offset(58.2, 57.4),
  );

  /// The badge: a green circle with a white ring centred on its edge
  /// (sketched at (66, 65), radius 15, ring 3).
  static const badgeCenter = Offset(
    (66 - 56.25) * _zoom + tile / 2,
    (65 - 54.25) * _zoom + tile / 2,
  );
  static const badgeRadius = 15 * _zoom;
  static const ringWidth = 3 * _zoom;

  /// The green part inside the ring.
  static const discRadius = badgeRadius - ringWidth / 2;

  /// The ring's outer edge. Single-colour versions cut the bell back to it
  /// so the badge stays separate.
  static const gapRadius = badgeRadius + ringWidth / 2;
}

enum IconStyle {
  /// Teal background, white bell, green badge with a white ring.
  full,

  /// No background (iOS dark: the system draws it), bell cut around the
  /// badge.
  dark,

  /// Grayscale with no background, for the system tint (iOS tinted).
  tinted,
}

/// Paints the 96-unit tile; [canvas] is already scaled to it.
void paintTile(Canvas canvas, IconStyle style) {
  final bell = AppIcon.bell.toPath();
  final thumb = AppIcon.thumb.toPath();
  final white = Paint()..color = AppIcon.white;

  if (style == IconStyle.full) {
    canvas
      ..drawRect(
        const Rect.fromLTWH(0, 0, AppIcon.tile, AppIcon.tile),
        Paint()
          ..shader = Gradient.linear(
            Offset.zero,
            const Offset(AppIcon.tile, AppIcon.tile),
            [AppIcon.tealLight, AppIcon.tealDark],
          ),
      )
      ..drawPath(bell, white)
      ..drawCircle(
        AppIcon.badgeCenter,
        AppIcon.badgeRadius,
        Paint()..color = AppIcon.green,
      )
      ..drawCircle(
        AppIcon.badgeCenter,
        AppIcon.badgeRadius,
        Paint()
          ..color = AppIcon.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = AppIcon.ringWidth,
      )
      ..drawPath(thumb, white);
    return;
  }

  canvas
    ..saveLayer(const Rect.fromLTWH(0, 0, AppIcon.tile, AppIcon.tile), Paint())
    ..drawPath(bell, white)
    ..drawCircle(
      AppIcon.badgeCenter,
      AppIcon.gapRadius,
      Paint()..blendMode = BlendMode.clear,
    )
    ..restore()
    ..drawCircle(
      AppIcon.badgeCenter,
      AppIcon.discRadius,
      Paint()
        ..color = style == IconStyle.dark ? AppIcon.green : AppIcon.tintedGray,
    )
    ..drawPath(thumb, white);
}

/// Renders the icon as a [size]×[size] image. With [circle], as an Android
/// launcher icon from before adaptive icons: a circle 44/48 of the size.
Future<Image> renderIcon({
  required int size,
  required IconStyle style,
  bool circle = false,
}) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  if (circle) {
    final diameter = size * 44 / 48;
    final inset = (size - diameter) / 2;
    canvas
      ..translate(inset, inset)
      ..scale(diameter / AppIcon.tile)
      ..clipPath(
        Path()..addOval(const Rect.fromLTWH(0, 0, AppIcon.tile, AppIcon.tile)),
      );
  } else {
    canvas.scale(size / AppIcon.tile);
  }
  paintTile(canvas, style);
  return recorder.endRecording().toImage(size, size);
}

// Android adaptive icon ------------------------------------------------------
//
// Adaptive icons are 108 dp; launchers show the inner 72 dp (through a mask)
// and keep the inner 66 dp circle safe. The tile maps onto the inner 72 dp.

const _dpScale = 72 / AppIcon.tile;
const _dpInset = 18.0;

String _dpPath(IconPath path) =>
    path.transform(scale: _dpScale, dx: _dpInset, dy: _dpInset).toPathData();

String _dp(double value) => formatNumber(value * _dpScale);

String _dpCircle(double radius, {bool clockwise = true}) {
  final cx = formatNumber(AppIcon.badgeCenter.dx * _dpScale + _dpInset);
  final cy = AppIcon.badgeCenter.dy * _dpScale + _dpInset;
  final r = radius * _dpScale;
  final top = formatNumber(cy - r);
  final bottom = formatNumber(cy + r);
  final arc = 'A${formatNumber(r)},${formatNumber(r)} 0 1,${clockwise ? 1 : 0}';
  return 'M$cx,$top $arc $cx,$bottom $arc $cx,${top}Z';
}

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

const _header =
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<!-- Generated by tool/app_icon/generate_app_icon_test.dart from\n'
    '     tool/app_icon/app_icon.dart. Change the design there and run it\n'
    '     again instead of editing this file. -->\n';

String _vector(String body, {bool aapt = false}) =>
    '$_header'
    '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
    '${aapt ? '    xmlns:aapt="http://schemas.android.com/aapt"\n' : ''}'
    '    android:width="108dp"\n'
    '    android:height="108dp"\n'
    '    android:viewportWidth="108"\n'
    '    android:viewportHeight="108">\n'
    '$body'
    '</vector>\n';

/// The teal gradient across the visible part.
String androidBackground() => _vector(aapt: true, '''
    <path android:pathData="M0,0H108V108H0Z">
        <aapt:attr name="android:fillColor">
            <gradient
                android:endX="90"
                android:endY="90"
                android:startX="18"
                android:startY="18"
                android:type="linear">
                <item android:color="${_hex(AppIcon.tealLight)}" android:offset="0" />
                <item android:color="${_hex(AppIcon.tealDark)}" android:offset="1" />
            </gradient>
        </aapt:attr>
    </path>
''');

/// Bell and badge.
String androidForeground() => _vector('''
    <path
        android:fillColor="${_hex(AppIcon.white)}"
        android:pathData="${_dpPath(AppIcon.bell)}" />
    <path
        android:fillColor="${_hex(AppIcon.green)}"
        android:pathData="${_dpCircle(AppIcon.badgeRadius)}"
        android:strokeColor="${_hex(AppIcon.white)}"
        android:strokeWidth="${_dp(AppIcon.ringWidth)}" />
    <path
        android:fillColor="${_hex(AppIcon.white)}"
        android:pathData="${_dpPath(AppIcon.thumb)}" />
''');

/// Android 13+ themed icon: one colour, so the bell is cut back around the
/// badge (the clip region's circle winds the other way, which leaves a hole)
/// and the thumb is cut out of the badge.
String androidMonochrome() => _vector('''
    <group>
        <clip-path android:pathData="M0,0H108V108H0Z ${_dpCircle(AppIcon.gapRadius, clockwise: false)}" />
        <path
            android:fillColor="${_hex(AppIcon.white)}"
            android:pathData="${_dpPath(AppIcon.bell)}" />
    </group>
    <path
        android:fillColor="${_hex(AppIcon.white)}"
        android:fillType="evenOdd"
        android:pathData="${_dpCircle(AppIcon.discRadius)} ${_dpPath(AppIcon.thumb)}" />
''');

const androidAdaptiveIcon =
    '$_header'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@drawable/ic_launcher_background" />\n'
    '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
    '    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n'
    '</adaptive-icon>\n';

// iOS ------------------------------------------------------------------------

/// A single-size app icon set (Xcode makes the other sizes) with dark and
/// tinted variants (iOS 18).
const iosIconFiles = {
  'AppIcon.png': IconStyle.full,
  'AppIcon-dark.png': IconStyle.dark,
  'AppIcon-tinted.png': IconStyle.tinted,
};

Map<String, Object> iosContents() => {
  'images': [
    for (final MapEntry(key: file, value: style) in iosIconFiles.entries)
      {
        if (style != IconStyle.full)
          'appearances': [
            {
              'appearance': 'luminosity',
              'value': style == IconStyle.dark ? 'dark' : 'tinted',
            },
          ],
        'filename': file,
        'idiom': 'universal',
        'platform': 'ios',
        'size': '1024x1024',
      },
  ],
  'info': {'author': 'xcode', 'version': 1},
};
