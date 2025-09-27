import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'api_config.dart';
import 'ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PorterPage extends StatefulWidget {
  const PorterPage({super.key});

  @override
  State<PorterPage> createState() => _PorterPageState();
}

class _PorterPageState extends State<PorterPage> {
  final String _baseUrl = ApiConfig.baseUrl;
  final MobileScannerController _controller = MobileScannerController();
  bool _locked = false;
  Map<String, dynamic>?
  _result; // { valid: bool, student: {...}, reason: string }
  String? _porterName;
  bool _scanning = true;
  bool _verifying = false;
  Timer? _expTimer;
  int? _expEpoch; // epoch seconds del token escaneado
  int _secondsLeft = 0;
  int _initialSeconds = 0;

  static final RegExp _jwtPattern = RegExp(
    r'^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$',
  );
  static final RegExp _urlTokenPattern = RegExp(
    r'[?&](?:t|token)=([^&]+)',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _porterName = prefs.getString('name') ?? 'Portero';
    });
  }

  void _reset() {
    setState(() {
      _locked = false;
      _result = null;
      _scanning = true;
      _stopCountdown();
    });
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_locked) return;
    final code = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
    if (code == null) return;
    setState(() {
      _locked = true;
      _scanning = false; // oculta la cÃ¡mara para evitar dobles capturas
    });
    final token = _extractToken(code.trim());
    _setupCountdownFromToken(token);
    await _verifyToken(token);
  }

  String _extractToken(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;

    final fromUrl = _tokenFromUrl(trimmed);
    if (fromUrl != null && fromUrl.isNotEmpty) {
      if (fromUrl.startsWith('http://') || fromUrl.startsWith('https://')) {
        final nested = _tokenFromUrl(fromUrl);
        if (nested != null && nested.isNotEmpty) return nested;
      }
      if (_jwtPattern.hasMatch(fromUrl)) return fromUrl;
      return fromUrl;
    }

    final labelled = RegExp(
      r'^(?:token|code)[:=]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (labelled != null) {
      final value = labelled.group(1)!.trim();
      if (value.isNotEmpty) {
        if (_jwtPattern.hasMatch(value)) return value;
        final nested = _tokenFromUrl(value);
        if (nested != null && nested.isNotEmpty) return nested;
        return value;
      }
    }

    final jwtMatch = _jwtPattern.firstMatch(trimmed);
    if (jwtMatch != null) return jwtMatch.group(0)!;

    final fallback = _urlTokenPattern.firstMatch(trimmed);
    if (fallback != null) {
      final value = Uri.decodeComponent(fallback.group(1)!).trim();
      if (value.isNotEmpty) return value;
    }

    return trimmed;
  }

  String? _tokenFromUrl(String text) {
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      return null;
    }
    String? candidate;
    try {
      final uri = Uri.parse(text);
      candidate = uri.queryParameters['t'] ?? uri.queryParameters['token'];
    } catch (_) {}
    candidate ??= _urlTokenPattern.firstMatch(text)?.group(1);
    if (candidate == null) return null;
    final value = Uri.decodeComponent(candidate).trim();
    return value.isEmpty ? null : value;
  }

  void _setupCountdownFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return;
      final payloadMap =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;
      final exp = (payloadMap['exp'] as num?)?.toInt();
      if (exp == null) return;
      _expEpoch = exp;
      _restartCountdown();
    } catch (_) {
      // ignorar: si no se puede leer exp, no hay contador
    }
  }

  void _restartCountdown() {
    _expTimer?.cancel();
    final exp = _expEpoch;
    if (exp == null) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final left = exp - now;
    if (left <= 0) return;
    _initialSeconds = left;
    _secondsLeft = left;
    _expTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          t.cancel();
        }
      });
    });
  }

  void _stopCountdown() {
    _expTimer?.cancel();
    _expTimer = null;
    _expEpoch = null;
    _secondsLeft = 0;
    _initialSeconds = 0;
  }

  Future<void> _verifyToken(String token) async {
    try {
      setState(() {
        _verifying = true;
      });
      final prefs = await SharedPreferences.getInstance();
      final auth = prefs.getString('token');
      final resp = await http
          .post(
            Uri.parse("$_baseUrl/verify"),
            headers: {
              'Content-Type': 'application/json',
              if (auth != null) 'Authorization': 'Bearer $auth',
            },
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      Map<String, dynamic> body;
      try {
        body = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        body = {};
      }
      if (resp.statusCode == 200 && (body['valid'] == true)) {
        setState(() {
          _result = {'valid': true, 'student': body['student']};
        });
      } else {
        final reason = (body['reason'] ?? 'invalid').toString();
        setState(() {
          _result = {'valid': false, 'reason': reason};
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = {'valid': false, 'reason': 'network_error'};
      });
    } finally {
      if (mounted) {
        setState(() {
          _verifying = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('role');
    await prefs.remove('name');
    await prefs.remove('code');
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }


@override
Widget build(BuildContext context) {
  if (kIsWeb) {
    final theme = Theme.of(context);
    return BrandScaffold(
      title: 'Panel del Portero',
      heroBackground: true,
      body: Center(
        child: FrostedPanel(
          width: 420,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.desktop_access_disabled_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: BrandSpacing.sm),
              Text(
                'Disponible solo en el dispositivo movil asignado.',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: BrandSpacing.xs),
              Text(
                'Usa el telefono autorizado para validar el ingreso con QR en vivo.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  final theme = Theme.of(context);
  final res = _result;

  return BrandScaffold(
    title: 'Panel del Portero',
    heroBackground: true,
    actions: [
      IconButton(
        tooltip: 'Cerrar sesion',
        onPressed: _logout,
        icon: const Icon(Icons.logout),
      ),
    ],
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FrostedPanel(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
          borderRadius: BrandRadii.large,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Usuario: ${_porterName ?? ''}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: BrandSpacing.xs),
              Text(
                'Escanea el QR del carnet para validar el acceso en tiempo real.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: BrandSpacing.md),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: res == null
                    ? const _PlaceholderMessage(key: ValueKey('placeholder'))
                    : _ResultCard(
                        key: ValueKey(res['valid'] == true),
                        result: res,
                      ),
              ),
              if (_secondsLeft > 0) ...[
                const SizedBox(height: BrandSpacing.sm),
                _ExpiryIndicator(secondsLeft: _secondsLeft, initial: _initialSeconds),
              ],
              const SizedBox(height: BrandSpacing.md),
              PrimaryButton(
                onPressed: _verifying ? null : _reset,
                expand: false,
                child: const Text('Escanear otro'),
              ),
              if (_verifying) ...[
                const SizedBox(height: BrandSpacing.sm),
                Row(
                  children: const [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: BrandSpacing.xs),
                    Text('Verificando...'),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: BrandSpacing.lg),
        Expanded(
          child: FrostedPanel(
            padding: const EdgeInsets.all(16),
            borderRadius: BrandRadii.large,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BrandRadii.medium),
              child: _scanning
                  ? MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                    )
                  : Container(
                      color: Colors.black.withValues(alpha: 0.06),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.pause_circle_outline,
                            size: 42,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: BrandSpacing.sm),
                          const Text('Camara pausada'),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ],
    ),
  );
}
}

class _PlaceholderMessage extends StatelessWidget {
  const _PlaceholderMessage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(BrandSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(BrandRadii.medium),
      ),
      child: Row(
        children: [
          Icon(
            Icons.qr_code_2_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: BrandSpacing.sm),
          Expanded(
            child: Text(
              'Apunta la camara al codigo QR para validar el ingreso.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> result;
  const _ResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = result['valid'] == true;
    final student = (result['student'] as Map?)?.cast<String, dynamic>();
    final base = ok ? theme.colorScheme.primary : theme.colorScheme.error;
    final title = ok ? 'Acceso permitido' : 'Acceso rechazado';
    String subtitle;
    if (ok) {
      final name = (student?['name'] ?? '').toString();
      final code = (student?['code'] ?? '').toString();
      final email = (student?['email'] ?? '').toString();
      final parts = <String>[];
      if (name.isNotEmpty) parts.add(name);
      if (code.isNotEmpty) parts.add('Codigo $code');
      if (email.isNotEmpty) parts.add(email);
      subtitle = parts.join(' · ');
      if (subtitle.isEmpty) {
        subtitle = 'Estudiante verificado';
      }
    } else {
      final reason = _reasonLabel((result['reason'] ?? 'invalid').toString());
      subtitle = 'Motivo: $reason';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(BrandRadii.medium),
        border: Border.all(color: base.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: base.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              ok ? Icons.check_rounded : Icons.close_rounded,
              color: base,
            ),
          ),
          const SizedBox(width: BrandSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(color: base),
                ),
                const SizedBox(height: BrandSpacing.xs),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _reasonLabel(String code) {
  switch (code) {
    case 'expired_or_unknown':
      return 'QR expirado o desconocido';
    case 'replayed':
      return 'QR ya utilizado';
    case 'missing_token':
    case 'invalid_token':
    case 'missing_jti':
      return 'QR invalido';
    case 'network_error':
      return 'Error de red';
    default:
      return code;
  }
}

class _ExpiryIndicator extends StatelessWidget {
  final int secondsLeft;
  final int initial;
  const _ExpiryIndicator({required this.secondsLeft, required this.initial});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = initial > 0 ? initial : (secondsLeft > 0 ? secondsLeft : 1);
    final remaining = secondsLeft.clamp(0, total);
    final progress = total == 0 ? 0.0 : 1 - (remaining / total);
    final color = remaining <= total * 0.2
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(BrandRadii.pill),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: progress.clamp(0.0, 1.0),
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            color: color,
          ),
        ),
        const SizedBox(height: BrandSpacing.xs),
        Text(
          'Tiempo restante: $remaining s',
          style: theme.textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}













