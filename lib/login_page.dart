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
            _error = 'Ingresa un codigo numerico de al menos 4 digitos.';
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
        String msg;
        if (resp.statusCode == 401) {
          msg =
              'Los datos ingresados no coinciden. Revisa tu correo o codigo y la contrasena.';
        } else if (resp.statusCode >= 500) {
          msg = 'El servicio no respondio. Intenta nuevamente en unos segundos.';
        } else {
          msg = 'No pudimos completar el inicio de sesion. Intenta nuevamente.';
        }
        try {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final err = (body['message'] ?? body['error'])?.toString();
          if (err != null && err.isNotEmpty) {
            msg = err;
          }
        } catch (_) {}
        setState(() {
          _error = msg;
        });
      }
    } on TimeoutException catch (_) {
      _startRetryCountdown();
      return;
    } catch (_) {
      setState(() {
        _error =
            'No se pudo conectar con el servidor. Verifica tu conexion e intenta nuevamente.';
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
      _error =
          'El servicio esta tardando en responder. Reintento automatico en $_retrySeconds s.';
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
          _error = 'Reintentando...';
        });
        _login();
      } else {
        setState(() {
          _retrySeconds -= 1;
          _error =
              'El servicio esta tardando en responder. Reintento automatico en $_retrySeconds s.';
        });
      }
    });
  }

  Future<void> _handleForgotPassword() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    final initialValue = _emailController.text.trim();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ForgotPasswordSheet(
        baseUrl: _baseUrl,
        initialIdentifier: initialValue.isNotEmpty ? initialValue : null,
      ),
    );
    if (!mounted) return;
    if (result == true) {
      _passController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Contrasena actualizada. Inicia sesion con la nueva contrasena.',
          ),
        ),
      );
    }
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
            onForgotPassword: () {
              if (_loading) return;
              _handleForgotPassword();
            },
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

enum _ForgotPasswordStep { identifier, otp, password }

class _ForgotPasswordSheet extends StatefulWidget {
  const _ForgotPasswordSheet({required this.baseUrl, this.initialIdentifier});

  final String baseUrl;
  final String? initialIdentifier;

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  final TextEditingController _identifierCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  _ForgotPasswordStep _step = _ForgotPasswordStep.identifier;
  bool _loading = false;
  String? _globalError;
  String? _otpError;
  String? _passwordError;
  String? _confirmError;
  String? _identifierValue;
  bool _identifierIsEmail = false;
  String? _maskedEmail;
  String? _debugOtp;
  String? _otpValue;
  String? _preflightToken;
  bool _newPasswordVisible = false;
  bool _confirmPasswordVisible = false;
  int _resends = 0;
  int _cooldownLeft = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    final prefill = widget.initialIdentifier?.trim();
    if (prefill != null && prefill.isNotEmpty) {
      _identifierCtrl.text = prefill;
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _identifierCtrl.dispose();
    _otpCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestReset({bool resend = false}) async {
    if (resend) {
      if (_resends >= 3) return;
      if (_cooldownLeft > 0) return;
    }
    final input = resend
        ? (_identifierValue ?? '')
        : _identifierCtrl.text.trim();
    if (input.isEmpty) {
      if (!resend) {
        setState(() {
          _globalError = 'Ingresa tu correo institucional o codigo.';
          _step = _ForgotPasswordStep.identifier;
        });
      }
      return;
    }
    final isEmail = input.contains('@');
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      if (!resend) {
        _globalError = null;
        _otpError = null;
      }
    });
    try {
      final uri = Uri.parse(
        widget.baseUrl,
      ).resolve('auth/password-reset/request');
      final body = isEmail ? {'email': input} : {'code': input};
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        Map<String, dynamic> data = {};
        try {
          data = jsonDecode(resp.body) as Map<String, dynamic>;
        } catch (_) {}
        setState(() {
          _identifierValue = input;
          _identifierIsEmail = isEmail;
          _maskedEmail = data['maskedEmail']?.toString();
          _debugOtp = data['debugOtp']?.toString();
          _otpError = null;
          _otpCtrl.clear();
          _passwordCtrl.clear();
          _confirmCtrl.clear();
          _otpValue = null;
          _preflightToken = null;
          _passwordError = null;
          _confirmError = null;
          _step = _ForgotPasswordStep.otp;
          if (!resend) {
            _globalError = null;
          }
          if (resend) {
            _resends += 1;
            _cooldownLeft = 30;
            _cooldownTimer?.cancel();
            _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
              if (!mounted) {
                t.cancel();
                return;
              }
              setState(() {
                if (_cooldownLeft > 0) {
                  _cooldownLeft -= 1;
                } else {
                  t.cancel();
                }
              });
            });
          }
        });
      } else {
        final message =
            _extractMessage(resp.body) ??
            'No se pudo enviar el codigo. Intentalo mas tarde.';
        setState(() {
          _globalError = message;
          if (!resend) {
            _step = _ForgotPasswordStep.identifier;
          }
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _globalError = 'Tiempo de espera agotado. Intentalo de nuevo.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _globalError = 'Error de red. Intentalo mas tarde.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  

  Future<void> _handleOtpContinue() async {
    final input = _otpCtrl.text.trim();
    if (input.isEmpty) {
      setState(() {
        _otpError = 'Ingresa el codigo recibido.';
      });
      return;
    }
    if (_identifierValue == null) {
      setState(() {
        _globalError = 'Solicita un codigo antes de continuar.';
        _step = _ForgotPasswordStep.identifier;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _otpError = null;
      _globalError = null;
    });

    try {
      final uri = Uri.parse(
        widget.baseUrl,
      ).resolve('auth/password-reset/confirm');
      final Map<String, dynamic> body = {
        'otp': input,
        'dryRun': true,
      };
      if (_identifierIsEmail) {
        body['email'] = _identifierValue;
      } else {
        body['code'] = _identifierValue;
      }
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        var data = <String, dynamic>{};
        try {
          final decoded = jsonDecode(resp.body);
          if (decoded is Map<String, dynamic>) {
            data = decoded;
          }
        } catch (_) {
          // Ignore if body is not a valid json map
        }

        final preflightToken = data['preflightToken'] as String?;
        if (preflightToken == null) {
          setState(() {
            _otpError = 'No se recibio el token de confirmacion del servidor.';
          });
          return;
        }

        setState(() {
          _otpValue = input;
          _preflightToken = preflightToken;
          _passwordError = null;
          _confirmError = null;
          _step = _ForgotPasswordStep.password;
        });
        return;
      }

      final data = _parseBody(resp.body);
      final errorCode = data['error']?.toString();
      final message =
          data['message']?.toString() ?? 'Codigo incorrecto o vencido.';

      if (errorCode == 'otp_invalid') {
        setState(() {
          _step = _ForgotPasswordStep.otp;
          _otpError = message;
        });
        return;
      }

      if (errorCode == 'otp_locked' ||
          errorCode == 'otp_expired' ||
          errorCode == 'otp_required') {
        setState(() {
          _step = _ForgotPasswordStep.identifier;
          _globalError = message;
          _otpCtrl.clear();
          _otpValue = null;
        });
        return;
      }

      setState(() {
        _otpError = message;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _otpError = 'Tiempo de espera agotado. Intentalo nuevamente.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _otpError = 'Error de red. Intentalo mas tarde.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  bool _isStrongPassword(String value) {
    if (value.length < 8) return false;
    final hasUpper = RegExp(r'[A-Z]').hasMatch(value);
    final hasLower = RegExp(r'[a-z]').hasMatch(value);
    final hasDigit = RegExp(r'\d').hasMatch(value);
    final hasSpecial = RegExp(r'[^A-Za-z0-9]').hasMatch(value);
    return hasUpper && hasLower && hasDigit && hasSpecial;
  }

  Future<void> _submitNewPassword() async {
    if (_identifierValue == null || _otpValue == null || _preflightToken == null) {
      setState(() {
        _globalError = 'Solicita un codigo antes de continuar.';
        _step = _ForgotPasswordStep.identifier;
      });
      return;
    }
    final password = _passwordCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (!_isStrongPassword(password)) {
      setState(() {
        _passwordError =
            'Debe tener minimo 8 caracteres, con mayusculas, minusculas, numero y simbolo.';
      });
      return;
    }
    if (password != confirm) {
      setState(() {
        _confirmError = 'Las contrasenas no coinciden.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _passwordError = null;
      _confirmError = null;
      _globalError = null;
    });

    try {
      final uri = Uri.parse(
        widget.baseUrl,
      ).resolve('auth/password-reset/confirm');
      final Map<String, dynamic> body = {
        'otp': _otpValue,
        'newPassword': password,
        'preflightToken': _preflightToken,
      };
      if (_identifierIsEmail) {
        body['email'] = _identifierValue;
      } else {
        body['code'] = _identifierValue;
      }
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        Navigator.of(context).pop(true);
        return;
      }

      final data = _parseBody(resp.body);
      final errorCode = data['error']?.toString();
      final message =
          data['message']?.toString() ?? 'No se pudo actualizar la contrasena.';

      if (errorCode == 'otp_invalid' || errorCode == 'otp_mismatch') {
        setState(() {
          _loading = false;
          _step = _ForgotPasswordStep.otp;
          _otpError = message;
        });
        return;
      }

      if (errorCode == 'otp_locked' ||
          errorCode == 'otp_expired' ||
          errorCode == 'otp_required' ||
          errorCode == 'invalid_preflight_token') {
        setState(() {
          _loading = false;
          _step = _ForgotPasswordStep.identifier;
          _globalError = message;
          _otpCtrl.clear();
          _otpValue = null;
          _preflightToken = null;
        });
        return;
      }

      if (errorCode == 'weak_password') {
        setState(() {
          _loading = false;
          _passwordError = message;
        });
        return;
      }

      setState(() {
        _loading = false;
        _globalError = message;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _passwordError = 'Tiempo de espera agotado. Intentalo nuevamente.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _passwordError = 'Error de red. Intentalo mas tarde.';
      });
    }
  }

  Map<String, dynamic> _parseBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return const {};
  }

  String? _extractMessage(String body) {
    final map = _parseBody(body);
    final message = map['message'] ?? map['error'];
    return message?.toString();
  }

  Widget _buildErrorBanner(String message) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: BrandSpacing.sm),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recuperar acceso',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _loading
                          ? null
                          : () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
                const SizedBox(height: BrandSpacing.sm),
                Text(
                  _step == _ForgotPasswordStep.identifier
                      ? 'Ingresa tu correo institucional o codigo para enviar el enlace/codigo de recuperacion.'
                      : _step == _ForgotPasswordStep.otp
                      ? 'Ingresa el codigo/token enviado a tu correo.'
                      : 'Define una nueva contrasena para tu cuenta.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_globalError != null) _buildErrorBanner(_globalError!),
                const SizedBox(height: BrandSpacing.sm),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _buildStepContent(theme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(ThemeData theme) {
    switch (_step) {
      case _ForgotPasswordStep.identifier:
        return _buildIdentifierStep(theme);
      case _ForgotPasswordStep.otp:
        return _buildOtpStep(theme);
      case _ForgotPasswordStep.password:
        return _buildPasswordStep(theme);
    }
  }

  Widget _buildIdentifierStep(ThemeData theme) {
    return Column(
      key: const ValueKey('identifier'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _identifierCtrl,
          decoration: const InputDecoration(
            labelText: 'Correo institucional o codigo',
            prefixIcon: Icon(Icons.account_circle_outlined),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          enabled: !_loading,
          onSubmitted: (_) => _loading ? null : _requestReset(),
        ),
        const SizedBox(height: BrandSpacing.md),
        PrimaryButton(
          onPressed: _loading ? null : _requestReset,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enviar codigo'),
        ),
        const SizedBox(height: BrandSpacing.xs),
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _buildOtpStep(ThemeData theme) {
    return Column(
      key: const ValueKey('otp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_maskedEmail != null)
          Padding(
            padding: const EdgeInsets.only(bottom: BrandSpacing.xs),
            child: Text(
              'Revisa ${_maskedEmail!} para obtener el codigo.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (_debugOtp != null)
          Padding(
            padding: const EdgeInsets.only(bottom: BrandSpacing.xs),
            child: Text(
              'Codigo (debug): $_debugOtp',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        TextField(
          controller: _otpCtrl,
          decoration: InputDecoration(
            labelText: 'Codigo o token',
            prefixIcon: const Icon(Icons.pin_outlined),
            errorText: _otpError,
          ),
          keyboardType: TextInputType.text,
          enabled: !_loading,
          onSubmitted: (_) {
            if (_loading) return;
            _handleOtpContinue();
          },
        ),
        const SizedBox(height: BrandSpacing.sm),
        PrimaryButton(
          onPressed: _loading ? null : () => _handleOtpContinue(),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continuar'),
        ),
        const SizedBox(height: BrandSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _resends >= 3
                  ? 'Reenvios agotados'
                  : _cooldownLeft > 0
                  ? 'Reenviar en ${_cooldownLeft}s'
                  : 'Puedes reenviar (/3)',
              style: theme.textTheme.bodySmall,
            ),
            TextButton(
              onPressed: _loading || _resends >= 3 || _cooldownLeft > 0
                  ? null
                  : () => _requestReset(resend: true),
              child: const Text('No recibi el codigo'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPasswordStep(ThemeData theme) {
    return Column(
      key: const ValueKey('password'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tu nueva contrasena debe tener minimo 8 caracteres, incluyendo mayusculas, minusculas, numeros y simbolos.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: BrandSpacing.sm),
        TextField(
          controller: _passwordCtrl,
          decoration: InputDecoration(
            labelText: 'Nueva contrasena',
            prefixIcon: const Icon(Icons.lock_outline),
            errorText: _passwordError,
            suffixIcon: IconButton(
              icon: Icon(
                _newPasswordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: _loading
                  ? null
                  : () {
                      setState(() {
                        _newPasswordVisible = !_newPasswordVisible;
                      });
                    },
            ),
          ),
          obscureText: !_newPasswordVisible,
          enabled: !_loading,
        ),
        const SizedBox(height: BrandSpacing.sm),
        TextField(
          controller: _confirmCtrl,
          decoration: InputDecoration(
            labelText: 'Confirmar contrasena',
            prefixIcon: const Icon(Icons.lock_outline),
            errorText: _confirmError,
            suffixIcon: IconButton(
              icon: Icon(
                _confirmPasswordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: _loading
                  ? null
                  : () {
                      setState(() {
                        _confirmPasswordVisible = !_confirmPasswordVisible;
                      });
                    },
            ),
          ),
          obscureText: !_confirmPasswordVisible,
          enabled: !_loading,
        ),
        const SizedBox(height: BrandSpacing.md),
        PrimaryButton(
          onPressed: _loading ? null : _submitNewPassword,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar nueva contrasena'),
        ),
        const SizedBox(height: BrandSpacing.xs),
        TextButton(
          onPressed: _loading
              ? null
              : () {
                  setState(() {
                    _step = _ForgotPasswordStep.otp;
                    _passwordError = null;
                    _confirmError = null;
                  });
                },
          child: const Text('Volver a ingresar codigo'),
        ),
      ],
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
