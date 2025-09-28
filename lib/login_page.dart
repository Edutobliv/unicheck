import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'ui_kit.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  Timer? _retryTimer;
  int _retrySeconds = 0;
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  bool _loading = false;
  bool _passwordVisible = false;
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
    FocusScope.of(context).unfocus();
    _retryTimer?.cancel();
    _retryTimer = null;
    _retrySeconds = 0;
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

      final loginUri = Uri.parse(_baseUrl).resolve('auth/login');

      final resp = await http
          .post(
            loginUri,
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
    } on TimeoutException catch (_) {
      _startRetryCountdown();
      return;
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

  void _startRetryCountdown() {
    _retryTimer?.cancel();
    _retrySeconds = 30;

    setState(() {
      _loading = false;
      _error = 'Estamos iniciando el servidor... reintento en $_retrySeconds s';
    });

    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_retrySeconds <= 1) {
        timer.cancel();
        _retrySeconds = 0;
        setState(() {
          _error =
              'Estamos iniciando el servidor... reintento en $_retrySeconds s';
        });
        _login();
      } else {
        setState(() {
          _retrySeconds -= 1;
          _error =
              'Estamos iniciando el servidor... reintento en $_retrySeconds s';
        });
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      title: 'Iniciar sesion',
      heroBackground: true,
      padding: EdgeInsets.zero,
      actions: [
        TextButton(
          onPressed: _loading
              ? null
              : () => Navigator.of(context).pushReplacementNamed('/register'),
          child: const Text('Crear cuenta'),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 980;
          final horizontalPadding = isWide ? 72.0 : 24.0;
          final verticalPadding = isWide ? 48.0 : 24.0;

          final hero = _LoginHero(
            compact: !isWide,
            onRegister: _loading
                ? null
                : () => Navigator.of(context).pushReplacementNamed('/register'),
          );
          final form = _LoginFormCard(
            emailController: _emailController,
            passController: _passController,
            loading: _loading,
            error: _error,
            passwordVisible: _passwordVisible,
            onTogglePasswordVisibility: () {
              setState(() {
                _passwordVisible = !_passwordVisible;
              });
            },
            onLogin: _loading ? null : _login,
            onForgotPassword: () {},
          );

          if (isWide) {
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: hero),
                  const SizedBox(width: BrandSpacing.xl),
                  Expanded(child: form),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              verticalPadding,
              horizontalPadding,
              BrandSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                hero,
                const SizedBox(height: BrandSpacing.xl),
                form,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LoginHero extends StatelessWidget {
  const _LoginHero({required this.compact, required this.onRegister});

  final bool compact;
  final VoidCallback? onRegister;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textAlign = compact ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const InfoBadge(
          icon: Icons.shield_outlined,
          label: 'Accesos protegidos en tiempo real',
        ),
        const SizedBox(height: BrandSpacing.lg),
        Text(
          'Bienvenido a Unicheck',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            letterSpacing: -0.6,
            height: 1.05,
          ),
          textAlign: textAlign,
        ),
        const SizedBox(height: BrandSpacing.sm),
        Text(
          'Gestiona tu credencial digital, sesiones de porteria y asistencia con seguridad empresarial.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.86),
          ),
          textAlign: textAlign,
        ),
        const SizedBox(height: BrandSpacing.lg),
        Wrap(
          alignment: compact ? WrapAlignment.center : WrapAlignment.start,
          spacing: BrandSpacing.sm,
          runSpacing: BrandSpacing.sm,
          children: const [
            _HeroChip(icon: Icons.qr_code_rounded, label: 'QR dinamico'),
            _HeroChip(icon: Icons.devices_other, label: 'Multiplataforma'),
            _HeroChip(icon: Icons.lock_clock, label: 'Estudiantes y Staff'),
          ],
        ),
      ],
    );
  }
}

class _LoginFormCard extends StatelessWidget {
  const _LoginFormCard({
    required this.emailController,
    required this.passController,
    required this.loading,
    required this.error,
    required this.passwordVisible,
    required this.onTogglePasswordVisibility,
    required this.onLogin,
    required this.onForgotPassword,
  });

  final TextEditingController emailController;
  final TextEditingController passController;
  final bool loading;
  final String? error;
  final bool passwordVisible;
  final VoidCallback onTogglePasswordVisibility;
  final VoidCallback? onLogin;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FrostedPanel(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 28),
      borderRadius: BrandRadii.large,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Inicia sesion', style: theme.textTheme.headlineSmall),
          const SizedBox(height: BrandSpacing.xs),
          Text(
            'Introduce tu correo institucional o tu codigo de estudiante para continuar.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: BrandSpacing.lg),
          TextField(
            controller: emailController,
            decoration: const InputDecoration(
              labelText: 'Correo institucional o codigo',
              prefixIcon: Icon(Icons.account_circle_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: BrandSpacing.sm),
          TextField(
            controller: passController,
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  passwordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: onTogglePasswordVisibility,
              ),
            ),
            obscureText: !passwordVisible,
            onSubmitted: (_) => onLogin?.call(),
          ),
          const SizedBox(height: BrandSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onForgotPassword,
              child: const Text('Olvide mi contraseña'),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: error == null
                ? const SizedBox(height: BrandSpacing.xs)
                : Padding(
                    key: ValueKey(error),
                    padding: const EdgeInsets.only(bottom: BrandSpacing.sm),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
          ),
          PrimaryButton(
            onPressed: onLogin,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: loading
                  ? const SizedBox(
                      key: ValueKey('loading'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Text('Ingresar a Unicheck'),
            ),
          ),
          const SizedBox(height: BrandSpacing.sm),
          SecondaryButton(
            onPressed: onLogin == null
                ? null
                : () => Navigator.of(context).pushReplacementNamed('/register'),
            child: const Text('Crear cuenta nueva'),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(BrandRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: BrandSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
