import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'api_config.dart';
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
      _scanning = false; // oculta la cámara para evitar dobles capturas
    });
    final token = _extractToken(code.trim());
    _setupCountdownFromToken(token);
    await _verifyToken(token);
  }

  String _extractToken(String raw) {
    // Accept URL like http://host/verify?t=XXX, or plain JWT
    try {
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        final uri = Uri.parse(raw);
        final t = uri.queryParameters['t'] ?? uri.queryParameters['token'];
        if (t != null && t.isNotEmpty) return t;
      }
    } catch (_) {}
    // Fallback: return raw as token
    return raw;
  }

  void _setupCountdownFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return;
      final payloadJson = utf8.decode(base64Url.normalize(parts[1]).codeUnits);
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
      if (mounted)
        setState(() {
          _verifying = false;
        });
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
    // En web, mostrar mensaje y no intentar usar cámara
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Panel del Portero'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'El panel de porterí­a no está disponible en la web.\nPor favor usa el celular vinculado a tu cuenta.',
            ),
          ),
        ),
      );
    }

    final res = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel del Portero'),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usuario: ${_porterName ?? ''} â€¢ Rol: Portero',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (res != null) ...[
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0, .05),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: anim,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  ),
                ),
                child: _ResultCard(
                  key: ValueKey(res['valid'] == true),
                  result: res,
                ),
              ),
              const SizedBox(height: 8),
              if (_secondsLeft > 0)
                _ExpiryIndicator(
                  secondsLeft: _secondsLeft,
                  initial: _initialSeconds,
                ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _verifying ? null : _reset,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Escanear otro'),
              ),
              const SizedBox(height: 12),
            ] else ...[
              const Text('Escanea el QR del estudiante para validar acceso.'),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _scanning
                    ? MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                      )
                    : Container(
                        color: Colors.black12,
                        child: const Center(child: Text('Cámara pausada')),
                      ),
              ),
            ),
            if (_verifying) ...[
              const SizedBox(height: 12),
              Row(
                children: const [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Verificando...'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> result;
  const _ResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final ok = result['valid'] == true;
    final student = (result['student'] as Map?)?.cast<String, dynamic>();
    final color = ok ? Colors.green.shade600 : Colors.red.shade700;
    final title = ok ? 'Válido' : 'No válido';
    String subtitle;
    if (ok) {
      subtitle =
          (student?['name'] ?? '').toString() +
          ' - ' +
          (student?['email'] ?? '').toString() +
          '\nCodigo: ' +
          (student?['code'] ?? '').toString();
    } else {
      subtitle =
          'Motivo: ' + _reasonLabel((result['reason'] ?? 'invalid').toString());
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, color: color, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(subtitle),
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
      return 'QR ya utilizado (repetido)';
    case 'missing_token':
    case 'invalid_token':
    case 'missing_jti':
      return 'QR inválido';
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
    final total = initial <= 0 ? 1 : initial;
    final value = (secondsLeft / total).clamp(0.0, 1.0);
    final color = secondsLeft > total * 0.5
        ? Colors.green
        : secondsLeft > total * 0.2
        ? Colors.orange
        : Colors.red;
    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            value: value,
            color: color,
            strokeWidth: 4,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Tiempo restante: ${secondsLeft}s',
          style: TextStyle(color: color),
        ),
      ],
    );
  }
}
