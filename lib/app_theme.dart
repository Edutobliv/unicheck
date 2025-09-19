import 'package:flutter/material.dart';

class BrandColors {
  static const Color emerald = Color(0xFF1B5E20);
  static const Color mint = Color(0xFFA5D6A7);
  static const Color charcoal = Color(0xFF101311);
  static const Color slate = Color(0xFF161B17);
  static const Color mist = Color(0xFFE6F4E5);
}

class AppThemes {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.mint,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF4F9F1),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: _textTheme(Brightness.light),
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _buttonStyle(scheme)),
      textButtonTheme: TextButtonThemeData(style: _textButtonStyle(scheme)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      inputDecorationTheme: _inputTheme(scheme, Brightness.light),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static TextTheme _textTheme(Brightness brightness) {
    final onSurface = brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF101512);
    const secondary = FontWeight.w500;
    return TextTheme(
      displaySmall: TextStyle(fontWeight: FontWeight.w700, color: onSurface),
      headlineMedium: TextStyle(
        fontWeight: FontWeight.w700,
        color: onSurface,
        height: 1.05,
      ),
      titleLarge: TextStyle(fontWeight: FontWeight.w600, color: onSurface),
      bodyLarge: TextStyle(
        fontWeight: secondary,
        color: onSurface.withValues(alpha: 0.88),
      ),
      bodyMedium: TextStyle(color: onSurface.withValues(alpha: 0.78)),
      labelLarge: TextStyle(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: onSurface,
      ),
    );
  }

  static ButtonStyle _buttonStyle(ColorScheme scheme) {
    return ButtonStyle(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.primary.withValues(alpha: 0.25);
        }
        return Color.alphaBlend(
          BrandColors.mint.withValues(alpha: 0.2),
          scheme.primary,
        );
      }),
      foregroundColor: WidgetStatePropertyAll(scheme.onPrimary),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 26, vertical: 16),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  static ButtonStyle _textButtonStyle(ColorScheme scheme) {
    return TextButton.styleFrom(
      foregroundColor: scheme.primary,
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
    );
  }

  static InputDecorationTheme _inputTheme(
    ColorScheme scheme,
    Brightness brightness,
  ) {
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: scheme.outlineVariant.withValues(
          alpha: brightness == Brightness.dark ? 0.6 : 1,
        ),
      ),
    );
    return InputDecorationTheme(
      filled: true,
      fillColor: brightness == Brightness.dark
          ? BrandColors.slate
          : BrandColors.mist,
      border: baseBorder,
      enabledBorder: baseBorder,
      focusedBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    );
  }
}

// Dark mode and toggle removed; no UI toggle remains.
