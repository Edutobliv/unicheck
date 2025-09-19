import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'api_config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  bool _loading = false;
  String? _error;
  final String _baseUrl = ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _checkToken();
  }

  Future<void> _checkToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final role = prefs.getString('role');
    if (token != null && role != null) {
      if (kIsWeb && role != 'teacher') {
        await prefs.remove('token');
        await prefs.remove('role');
        await prefs.remove('name');
        await prefs.remove('code');
        if (mounted) {
          setState(() {
            _error =
                'Acceso web exclusivo para docentes. Ingresa desde tu celular vinculado.';
          });
        }
        return;
      }
      if (!mounted) return;
      String route;
      if (role == 'teacher') {
        route = '/teacher';
      } else if (role == 'porter') {
        route = '/porter';
      } else {
        route = '/carnet';
      }
      Navigator.of(context).pushReplacementNamed(route);
    }
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final input = _emailController.text.trim();
      final isEmail = input.contains('@');
      if (!isEmail) {
        final codeOk = RegExp(r'^\d{4,}$').hasMatch(input);
        if (!codeOk) {
          setState(() {
            _error =
                'El codigo debe ser numerico (min. 4 digitos). Origen: validacion local.';
          });
          return;
        }
      }

      final Map<String, String> payload = isEmail
          ? {'email': input, 'password': _passController.text}
          : {'code': input, 'password': _passController.text};

      final resp = await http
          .post(
            Uri.parse('$_baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        final prevCode = prefs.getString('code');
        await prefs.setString('token', data['token'] as String);
        if (data['refreshToken'] is String) {
          await prefs.setString('refreshToken', data['refreshToken'] as String);
        }
        final user = (data['user'] as Map).cast<String, dynamic>();
        final code = user['code'] as String;
        if (prevCode != null && prevCode != code) {
          await prefs.remove('photoData:$prevCode');
          await prefs.remove('photoUrl:$prevCode');
          await prefs.remove('photoUrlExp:$prevCode');
        }
        await prefs.setString('role', user['role'] as String);
        await prefs.setString('code', code);
        await prefs.setString('name', user['name'] as String);
        if (user['expiresAt'] is String) {
          await prefs.setString('expiresAt', user['expiresAt'] as String);
        }
        if (user['program'] is String) {
          await prefs.setString('program', user['program'] as String);
        }
        await prefs.remove('photoUrl');
        await prefs.remove('photoUrlExp');
        if (user['photoUrl'] is String) {
          await prefs.setString('photoUrl:$code', user['photoUrl'] as String);
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          await prefs.setInt('photoUrlExp:$code', now + 300);
        } else {
          await prefs.remove('photoUrl:$code');
          await prefs.remove('photoUrlExp:$code');
        }
        final role = user['role'] as String?;
        if (kIsWeb && role != 'teacher') {
          await prefs.remove('token');
          await prefs.remove('role');
          await prefs.remove('name');
          await prefs.remove('code');
          if (mounted) {
            setState(() {
              _error = role == 'porter'
                  ? 'El panel de porteria solo esta disponible desde el celular vinculado.'
                  : 'El carnet de estudiantes solo esta disponible desde el celular vinculado.';
            });
          }
          return;
        }
        if (!mounted) return;
        String route;
        if (user['role'] == 'teacher') {
          route = '/teacher';
        } else if (user['role'] == 'porter') {
          route = '/porter';
        } else {
          route = '/carnet';
        }
        Navigator.of(context).pushReplacementNamed(route);
      } else {
        String msg = 'Credenciales invalidas';
        try {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final err = (body['message'] ?? body['error'])?.toString();
          if (err != null && err.isNotEmpty) {
            msg = '$err (Origen: backend ${resp.statusCode})';
          } else {
            msg = 'Error (Origen: backend ${resp.statusCode})';
          }
        } catch (_) {}
        setState(() {
          _error = msg;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error de red: ${e.toString()} (Origen: red)';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Unicheck',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: theme.colorScheme.onInverseSurface,
          ),
        ),
      ),
      body: Stack(
        children: [
          const _BackgroundCanvas(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 860;
                final contentPadding = EdgeInsets.symmetric(
                  horizontal: isWide ? 64 : 24,
                  vertical: isWide ? 48 : 24,
                );
                final hero = _HeroPane(isWide: isWide);
                final card = _LoginCard(
                  emailController: _emailController,
                  passController: _passController,
                  loading: _loading,
                  error: _error,
                  onLogin: _loading ? null : _login,
                  onRegister: () =>
                      Navigator.of(context).pushNamed('/register'),
                );

                if (isWide) {
                  return Padding(
                    padding: contentPadding,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: hero),
                        const SizedBox(width: 56),
                        card,
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: contentPadding.copyWith(bottom: 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [hero, const SizedBox(height: 40), card],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }
}

class _BackgroundCanvas extends StatelessWidget {
  const _BackgroundCanvas();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF0B0D0B), BrandColors.charcoal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: const [
          Positioned(
            top: -140,
            left: -120,
            child: _GlowCircle(color: Color(0xB3A5D6A7), size: 340),
          ),
          Positioned(
            bottom: -160,
            right: -140,
            child: _GlowCircle(color: Color(0xB31B5E20), size: 420),
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowCircle({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0.0)],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

class _HeroPane extends StatelessWidget {
  final bool isWide;
  const _HeroPane({required this.isWide});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onDark = theme.colorScheme.onInverseSurface;
    final headline = theme.textTheme.headlineMedium?.copyWith(
      fontSize: isWide ? 50 : 40,
      height: 1.05,
      letterSpacing: -0.5,
      color: onDark,
    );
    final body = theme.textTheme.bodyLarge?.copyWith(
      fontSize: isWide ? 18 : 16,
      color: onDark.withValues(alpha: 0.88),
    );
    return Column(
      crossAxisAlignment: isWide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Align(
          alignment: isWide ? Alignment.centerLeft : Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: BrandColors.mint.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: BrandColors.mint.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shield_moon_outlined,
                  size: 18,
                  color: theme.colorScheme.inversePrimary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Control inteligente de asistencia',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.inversePrimary,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Unicheck - carnet digital',
          style: headline,
          textAlign: isWide ? TextAlign.left : TextAlign.center,
        ),
        const SizedBox(height: 18),
        Text(
          'Unicheck centraliza accesos, monitoreo y alertas para tu comunidad educativa en un solo lugar.',
          style: body,
          textAlign: isWide ? TextAlign.left : TextAlign.center,
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: isWide ? WrapAlignment.start : WrapAlignment.center,
          children: const [
            _FeatureChip(
              icon: Icons.qr_code_scanner,
              label: 'Porteria con QR en vivo',
            ),
            _FeatureChip(
              icon: Icons.auto_graph_rounded,
              label: 'Reportes potenciados por IA',
            ),
            _FeatureChip(
              icon: Icons.groups_rounded,
              label: 'Seguimiento docente y alumno',
            ),
          ],
        ),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onDark = theme.colorScheme.onInverseSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BrandColors.mint.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: onDark.withValues(alpha: 0.92)),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: onDark.withValues(alpha: 0.92),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passController;
  final bool loading;
  final String? error;
  final VoidCallback? onLogin;
  final VoidCallback onRegister;

  const _LoginCard({
    required this.emailController,
    required this.passController,
    required this.loading,
    required this.error,
    required this.onLogin,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final cardColor = theme.colorScheme.surface.withValues(
      alpha: brightness == Brightness.dark ? 0.82 : 0.96,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.18),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.16),
              blurRadius: 38,
              spreadRadius: 0,
              offset: const Offset(0, 28),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(32, 36, 32, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Inicia sesion',
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 26,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Introduce tu correo institucional o tu codigo de estudiante para continuar.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.74),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Correo o codigo',
                prefixIcon: Icon(Icons.person_outline),
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: passController,
              decoration: const InputDecoration(
                labelText: 'Contrasena',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              obscureText: true,
              onSubmitted: (_) => onLogin?.call(),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: error == null
                  ? const SizedBox(height: 0)
                  : Padding(
                      key: ValueKey(error),
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onLogin,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: loading
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Padding(
                          key: ValueKey('text'),
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text('Entrar a Unicheck'),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Divider(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Nuevo por aqui?',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.68,
                      ),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onRegister,
                child: const Text('Crear cuenta'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
