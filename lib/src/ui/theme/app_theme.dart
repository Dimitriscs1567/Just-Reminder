import 'package:material_ui/material_ui.dart';

/// Brand colors. Material You (wallpaper colors) replaces the indigo/teal
/// pair on Android 12+; positive and negative always stay green and red.
abstract final class BrandColors {
  static const indigo = Color(0xFF4F46E5);
  static const teal = Color(0xFF14B8A6);
  static const positive = Color(0xFF1E8E3E);
  static const negative = Color(0xFFD93025);
}

/// The indigo & teal scheme used when the platform has no dynamic colors.
ColorScheme fallbackColorScheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: BrandColors.indigo,
    brightness: brightness,
  );
  final teal = ColorScheme.fromSeed(
    seedColor: BrandColors.teal,
    brightness: brightness,
  );
  return base.copyWith(
    tertiary: teal.primary,
    onTertiary: teal.onPrimary,
    tertiaryContainer: teal.primaryContainer,
    onTertiaryContainer: teal.onPrimaryContainer,
  );
}

/// The app theme for [scheme] (light or dark).
ThemeData buildAppTheme(ColorScheme scheme) {
  final baseText = ThemeData(colorScheme: scheme).textTheme;
  final radius16 = BorderRadius.circular(16);

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [StatusColors.forScheme(scheme)],
    textTheme: baseText.copyWith(
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      titleLarge: baseText.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: baseText.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      // In dark mode the lowest container is too close to the background.
      color: scheme.brightness == Brightness.dark
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      border: OutlineInputBorder(
        borderRadius: radius16,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius16,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius16,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius16,
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius16,
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 4),
    ),
  );
}

/// Positive (green, thumbs up) and negative (red, thumbs down) colors as
/// Material 3 tonal roles: a strong color for the thumb and buttons, and a
/// soft container for backgrounds. They are deliberately *not* harmonized
/// with the wallpaper colors, which would push red towards pink.
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.positive,
    required this.onPositive,
    required this.positiveContainer,
    required this.onPositiveContainer,
    required this.negative,
    required this.onNegative,
    required this.negativeContainer,
    required this.onNegativeContainer,
  });

  factory StatusColors.forScheme(ColorScheme scheme) {
    ColorScheme tones(Color seed, DynamicSchemeVariant variant) =>
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: scheme.brightness,
          dynamicSchemeVariant: variant,
        );
    // Solid colors (thumb, buttons, badges) are vivid; backgrounds use the
    // calmer tonal containers (the vivid ones turn neon green).
    final positive = tones(BrandColors.positive, DynamicSchemeVariant.vibrant);
    final negative = tones(BrandColors.negative, DynamicSchemeVariant.vibrant);
    final positiveSoft = tones(
      BrandColors.positive,
      DynamicSchemeVariant.tonalSpot,
    );
    final negativeSoft = tones(
      BrandColors.negative,
      DynamicSchemeVariant.tonalSpot,
    );
    // In dark mode the solid colors stay saturated mid-tones with white
    // content; Material's dark-mode tones look washed out (red) or neon
    // (green).
    final light = scheme.brightness == Brightness.light;
    return StatusColors(
      positive: light ? positive.primary : BrandColors.positive,
      onPositive: light ? positive.onPrimary : Colors.white,
      positiveContainer: positiveSoft.primaryContainer,
      // Text from the vivid palette stays clearly green/red (the tonal one
      // drifts towards brown).
      onPositiveContainer: positive.onPrimaryContainer,
      negative: light ? negative.primary : BrandColors.negative,
      onNegative: light ? negative.onPrimary : Colors.white,
      negativeContainer: negativeSoft.primaryContainer,
      onNegativeContainer: negative.onPrimaryContainer,
    );
  }

  final Color positive;
  final Color onPositive;
  final Color positiveContainer;
  final Color onPositiveContainer;
  final Color negative;
  final Color onNegative;
  final Color negativeContainer;
  final Color onNegativeContainer;

  @override
  StatusColors copyWith({
    Color? positive,
    Color? onPositive,
    Color? positiveContainer,
    Color? onPositiveContainer,
    Color? negative,
    Color? onNegative,
    Color? negativeContainer,
    Color? onNegativeContainer,
  }) => StatusColors(
    positive: positive ?? this.positive,
    onPositive: onPositive ?? this.onPositive,
    positiveContainer: positiveContainer ?? this.positiveContainer,
    onPositiveContainer: onPositiveContainer ?? this.onPositiveContainer,
    negative: negative ?? this.negative,
    onNegative: onNegative ?? this.onNegative,
    negativeContainer: negativeContainer ?? this.negativeContainer,
    onNegativeContainer: onNegativeContainer ?? this.onNegativeContainer,
  );

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return StatusColors(
      positive: mix(positive, other.positive),
      onPositive: mix(onPositive, other.onPositive),
      positiveContainer: mix(positiveContainer, other.positiveContainer),
      onPositiveContainer: mix(onPositiveContainer, other.onPositiveContainer),
      negative: mix(negative, other.negative),
      onNegative: mix(onNegative, other.onNegative),
      negativeContainer: mix(negativeContainer, other.negativeContainer),
      onNegativeContainer: mix(onNegativeContainer, other.onNegativeContainer),
    );
  }
}

extension StatusColorsContext on BuildContext {
  StatusColors get statusColors => Theme.of(this).extension<StatusColors>()!;
}
