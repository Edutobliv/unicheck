import 'package:flutter/material.dart';

class BrandColors {
  static const Color primary = Color(0xFF0FD7B9);
  static const Color primaryBright = Color(0xFF05E2CF);
  static const Color primaryDark = Color(0xFF02BFAE);
  static const Color primaryOnLight = Color(0xFF00856C);
  static const Color aqua = Color(0xFF00C0DC);
  static const Color navy = Color(0xFF0E1A2C);
  static const Color navySoft = Color(0xFF152941);
  static const Color slate = Color(0xFF20344A);
  static const Color background = Color(0xFFF4F7FB);
  static const Color backgroundAlt = Color(0xFFE8EFF7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFF8FAFD);
  static const Color outline = Color(0xFFAEC3D7);
  static const Color outlineStrong = Color(0xFF7990A5);
  static const Color success = Color(0xFF38D39F);
  static const Color warning = Color(0xFFF1B24A);
  static const Color error = Color(0xFFEB5757);
}

class AppThemes {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: BrandColors.primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFD3F8F0),
      onPrimaryContainer: BrandColors.navy,
      secondary: BrandColors.aqua,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFD6F6FF),
      onSecondaryContainer: BrandColors.navy,
      tertiary: Color(0xFF4D7BE5),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFE0E8FF),
      onTertiaryContainer: BrandColors.navy,
      error: BrandColors.error,
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: BrandColors.surface,
      onSurface: BrandColors.navy,
      surfaceContainerHighest: Color(0xFFE2EAF3),
      onSurfaceVariant: Color(0xFF455467),
      outline: BrandColors.outline,
      outlineVariant: Color(0xFFCDD8E4),
      inverseSurface: BrandColors.navy,
      onInverseSurface: Colors.white,
      inversePrimary: Color(0xFF6CEBD8),
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: BrandColors.primary,
    );

    final textTheme = _textTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface.withValues(alpha: 0.94),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: BrandColors.navy,
        behavior: SnackBarBehavior.floating,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _primaryButtonStyle(scheme),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _primaryButtonStyle(scheme),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.45), width: 1.2),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.15),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      inputDecorationTheme: _inputTheme(scheme),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 32,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        labelStyle: textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        iconTheme: IconThemeData(color: scheme.primary, size: 18),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        tileColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        iconColor: scheme.primary,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodyMedium,
      ),
    );
  }

  static ButtonStyle _primaryButtonStyle(ColorScheme scheme) {
    return ButtonStyle(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.primary.withValues(alpha: 0.35);
        }
        return scheme.primary;
      }),
      foregroundColor: WidgetStateProperty.all<Color>(scheme.onPrimary),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.25),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  static TextTheme _textTheme() {
    const baseColor = BrandColors.navy;
    return const TextTheme(
      displayMedium: TextStyle(
        fontSize: 46,
        fontWeight: FontWeight.w700,
        height: 1.04,
        letterSpacing: -1.0,
        color: baseColor,
      ),
      headlineMedium: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.05,
        color: baseColor,
      ),
      headlineSmall: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.1,
        color: baseColor,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: baseColor,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: baseColor,
      ),
      titleSmall: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.45,
        color: Color(0xFF345064),
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: Color(0xFF4B6075),
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Color(0xFF5F768C),
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.35,
        color: baseColor,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: baseColor,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: baseColor,
      ),
    );
  }

  static InputDecorationTheme _inputTheme(ColorScheme scheme) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.55), width: 1.2),
    );
    final focusedBorder = border.copyWith(
      borderSide: BorderSide(color: scheme.primary, width: 1.8),
    );
    return InputDecorationTheme(
      filled: true,
      fillColor: BrandColors.surfaceSoft,
      border: border,
      enabledBorder: border,
      focusedBorder: focusedBorder,
      errorBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.error, width: 1.4),
      ),
      focusedErrorBorder: focusedBorder.copyWith(
        borderSide: BorderSide(color: scheme.error, width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.88)),
      helperStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.76)),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
      prefixIconColor: scheme.onSurfaceVariant.withValues(alpha: 0.75),
    );
  }
}
