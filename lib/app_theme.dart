import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemes {
  static const Color _seedLight = Color(0xFFA5D6A7); // verde pastel
  static const Color _seedDark = Color(0xFF1B5E20); // verde oscuro

  static ThemeData light() {
    final cs = ColorScheme.fromSeed(seedColor: _seedLight, brightness: Brightness.light);
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: Colors.white,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: cs.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.inverseSurface,
        contentTextStyle: TextStyle(color: cs.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData dark() {
    final cs = ColorScheme.fromSeed(seedColor: _seedDark, brightness: Brightness.dark);
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: const Color(0xFF111213),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: const Color(0xFF111213),
        foregroundColor: cs.onSurface,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: cs.surface,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.inverseSurface,
        contentTextStyle: TextStyle(color: cs.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class ThemeController extends StatefulWidget {
  final Widget child;
  const ThemeController({super.key, required this.child});

  static _ThemeControllerState? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ThemeScope>();
    return scope?.state;
  }

  static _ThemeControllerState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ThemeScope>();
    assert(scope != null, 'ThemeController.of() called with no ThemeController ancestor');
    return scope!.state;
  }

  @override
  State<ThemeController> createState() => _ThemeControllerState();
}

class _ThemeControllerState extends State<ThemeController> {
  static const _prefKey = 'theme_mode';
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_prefKey);
    setState(() {
      _mode = _fromString(s) ?? ThemeMode.system;
    });
  }

  Future<void> setMode(ThemeMode m) async {
    setState(() => _mode = m);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _toString(m));
  }

  Future<void> toggle() async {
    if (_mode == ThemeMode.dark) {
      await setMode(ThemeMode.light);
    } else {
      await setMode(ThemeMode.dark);
    }
  }

  static String _toString(ThemeMode m) {
    switch (m) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
      default:
        return 'system';
    }
  }

  static ThemeMode? _fromString(String? s) {
    if (s == 'dark') return ThemeMode.dark;
    if (s == 'light') return ThemeMode.light;
    if (s == 'system') return ThemeMode.system;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _ThemeScope(state: this, mode: _mode, child: widget.child);
  }
}

class _ThemeScope extends InheritedWidget {
  final _ThemeControllerState state;
  final ThemeMode mode; // snapshot in time to detect changes
  const _ThemeScope({required this.state, required this.mode, required super.child});

  @override
  bool updateShouldNotify(covariant _ThemeScope oldWidget) => oldWidget.mode != mode;
}

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeController.maybeOf(context);
    final mode = controller?.mode ?? ThemeMode.system;
    final isDark = mode == ThemeMode.dark;
    final tooltip = () {
      switch (mode) {
        case ThemeMode.dark:
          return 'Modo: oscuro (toca: claro, mantén: sistema)';
        case ThemeMode.light:
          return 'Modo: claro (toca: oscuro, mantén: sistema)';
        case ThemeMode.system:
        default:
          return 'Modo: sistema (toca: oscuro)';
      }
    }();

    return GestureDetector(
      onLongPress: () => controller?.setMode(ThemeMode.system),
      child: IconButton(
        tooltip: tooltip,
        onPressed: () {
          if (controller == null) return;
          if (mode == ThemeMode.system) {
            controller.setMode(ThemeMode.dark);
          } else {
            controller.toggle();
          }
        },
        icon: Icon(
          mode == ThemeMode.system
              ? Icons.brightness_auto_rounded
              : (isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round),
        ),
      ),
    );
  }
}
