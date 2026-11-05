import 'package:material_ui/material_ui.dart';

/// Brand colors. Material You (wallpaper colors) replaces the indigo/teal
/// pair on Android 12+; a due reminder always stays teal ([StatusColors]).
abstract final class BrandColors {
  static const indigo = Color(0xFF4F46E5);
  static const teal = Color(0xFF14B8A6);

  /// The app's main teal (the end of the icon's gradient).
  static const dueTeal = Color(0xFF0F766E);
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

/// The colors of a due (firing) reminder: the app's teal, deliberately the
/// same with or without wallpaper colors. A strong color for the ring,
/// thumb and Done button, a soft container for backgrounds. Missed and done
/// use the scheme's neutral colors (`outline`, `onSurfaceVariant`), never
/// red or green.
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.due,
    required this.onDue,
    required this.dueContainer,
    required this.onDueContainer,
  });

  factory StatusColors.forScheme(ColorScheme scheme) =>
      scheme.brightness == Brightness.light
      ? const StatusColors(
          due: BrandColors.dueTeal,
          onDue: Colors.white,
          dueContainer: Color(0xFFD5F5EE),
          onDueContainer: Color(0xFF04342C),
        )
      : const StatusColors(
          due: Color(0xFF2DD4BF),
          onDue: Color(0xFF00201C),
          dueContainer: Color(0xFF113F3A),
          onDueContainer: Color(0xFFB4F2E6),
        );

  final Color due;
  final Color onDue;
  final Color dueContainer;
  final Color onDueContainer;

  @override
  StatusColors copyWith({
    Color? due,
    Color? onDue,
    Color? dueContainer,
    Color? onDueContainer,
  }) => StatusColors(
    due: due ?? this.due,
    onDue: onDue ?? this.onDue,
    dueContainer: dueContainer ?? this.dueContainer,
    onDueContainer: onDueContainer ?? this.onDueContainer,
  );

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return StatusColors(
      due: mix(due, other.due),
      onDue: mix(onDue, other.onDue),
      dueContainer: mix(dueContainer, other.dueContainer),
      onDueContainer: mix(onDueContainer, other.onDueContainer),
    );
  }
}

extension StatusColorsContext on BuildContext {
  StatusColors get statusColors => Theme.of(this).extension<StatusColors>()!;
}
