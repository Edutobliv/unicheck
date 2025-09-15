import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart';
import 'teacher_page.dart';
import 'student_checkin_scanner.dart';
import 'porter_page.dart';
import 'app_theme.dart';
import 'api_config.dart';
import 'register_page.dart';

void main() {
  runApp(ThemeController(child: const App()));
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.maybeOf(context);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppThemes.light(),
      darkTheme: AppThemes.dark(),
      themeMode: theme?.mode ?? ThemeMode.system,
      routes: {
        '/carnet': (_) => const CarnetPage(),
        '/login': (_) => const LoginPage(),
        '/teacher': (_) => const TeacherPage(),
        '/porter': (_) => const PorterPage(),
        '/scan-checkin': (_) => const StudentCheckInScanner(),
        '/register': (_) => const RegisterPage(),
      },
      home: const LoginPage(),
    );
  }
}

class CarnetPage extends StatefulWidget {
  const CarnetPage({super.key});
  @override
  State<CarnetPage> createState() => _CarnetPageState();
}

class _CarnetPageState extends State<CarnetPage> {
  final String _baseUrl = ApiConfig.baseUrl; // backend por plataforma

  String? _qrUrl;
  int _secondsLeft = 0;
  Timer? _timer;
  Map<String, dynamic>? _student;
  String? _ephemeralCode;

  // Colores / estilos
  static const Color rojoMarca = Color(0xFFB0191D);
  static const Color grisTexto = Color(0xFF424242);

  // Tamaños (ajustados para parecerse a la maqueta)
  static const double kPaddingTarjeta = 16;
  static const double kFotoW = 150; // ↑
  static const double kFotoH = 175; // ↑
  static const double kQrSize = 190; // ↑ QR más grande

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _primeFromPrefs().whenComplete(_fetchQr);
    }
  }

  Future<void> _primeFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _student = {
          if (prefs.getString('code') != null) 'code': prefs.getString('code'),
          if (prefs.getString('name') != null) 'name': prefs.getString('name'),
          if (prefs.getString('program') != null) 'program': prefs.getString('program'),
          if (prefs.getString('expiresAt') != null) 'expiresAt': prefs.getString('expiresAt'),
          if (prefs.getString('photoUrl') != null) 'photoUrl': prefs.getString('photoUrl'),
        }..removeWhere((k, v) => v == null);
      });
    } catch (_) {}
  }

  Future<void> _fetchQr() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        if (mounted) Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
      final resp = await http.post(
        Uri.parse("$_baseUrl/issue-ephemeral"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _qrUrl = data["qrUrl"] as String;
          _secondsLeft = (data["ttl"] as num).toInt();
          _student = (data["student"] as Map?)?.cast<String, dynamic>();
          _ephemeralCode = data["ephemeralCode"] as String?;
        });
        // Guardar foto firmada y expiración si viene en la respuesta
        final stu = _student;
        if (stu != null) {
          final signed = stu['photoUrl'] as String?;
          final expIn = (stu['photoUrlExpiresIn'] as num?)?.toInt() ?? 0;
          if (signed != null && signed.isNotEmpty && expIn > 0) {
            final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            final expAt = now + expIn;
            await prefs.setString('photoUrl', signed);
            await prefs.setInt('photoUrlExp', expAt);
          } else {
            // Si no vino firmada, intenta refrescar si está expirada o no existe
            await _maybeRefreshSignedPhoto(prefs);
          }
        }
        _startCountdown();
      } else {
        _toast("No se pudo generar el QR (${resp.statusCode})");
      }
    } catch (e) {
      _toast("Error de red: $e");
    }
  }

  Future<void> _maybeRefreshSignedPhoto(SharedPreferences? givenPrefs) async {
    try {
      final prefs = givenPrefs ?? await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expAt = prefs.getInt('photoUrlExp') ?? 0;
      final cached = prefs.getString('photoUrl');
      final stillValid = cached != null && cached.isNotEmpty && expAt > now + 5;
      if (stillValid) {
        if (!mounted) return;
        setState(() {
          (_student ??= <String, dynamic>{})['photoUrl'] = cached;
        });
        return;
      }
      final resp = await http.get(
        Uri.parse("$_baseUrl/users/me/photo-url"),
        headers: { 'Authorization': 'Bearer $token' },
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final m = jsonDecode(resp.body) as Map<String, dynamic>;
        final signed = m['photoUrl'] as String?;
        final expIn = (m['expiresIn'] as num?)?.toInt() ?? 0;
        if (signed != null && signed.isNotEmpty && expIn > 0) {
          final newExp = now + expIn;
          await prefs.setString('photoUrl', signed);
          await prefs.setInt('photoUrlExp', newExp);
          if (!mounted) return;
          setState(() {
            (_student ??= <String, dynamic>{})['photoUrl'] = signed;
          });
        }
      }
    } catch (_) {}
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _fetchQr();
      }
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
      return Scaffold(
        appBar: AppBar(
          title: const Text("Carnet Digital"),
          actions: const [ThemeToggleButton()],
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('El carnet digital está disponible solo en la app móvil.\nPor favor ingresa desde tu celular vinculado.'),
          ),
        ),
      );
    }

    final s = _student;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Carnet Digital"),
        actions: [
          IconButton(
            tooltip: 'Registrar asistencia (scan)',
            onPressed: () => Navigator.of(context).pushNamed('/scan-checkin'),
            icon: const Icon(Icons.qr_code_scanner),
          ),
          const ThemeToggleButton(),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // TARJETA
            Container(
              padding: const EdgeInsets.all(kPaddingTarjeta),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(blurRadius: 8, color: Colors.black12),
                ],
                border: Border.all(color: const Color(0xFFE9E9E9)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Encabezado con logo + nombre universidad
                  Center(
                    child: Image.asset(
                      "assets/img/logo_piloto.png",
                      height: 90, // ajusta el tamaño del logo
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Foto + QR (centrados y proporcionados)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: _FotoBox(
                            photoAssetPath: "assets/img/foto_carnet.png",
                            photoUrl: s?["photoUrl"],
                            width: 160,
                            height: 200,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _QrGrande(qrUrl: _qrUrl, size: kQrSize),
                              if (_ephemeralCode != null) ...[
                                const SizedBox(height: 8),
                                Text('Código: ' + _ephemeralCode!, style: const TextStyle(fontSize: 12)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // NOMBRE
                  const _Label("NOMBRE"),
                  Text(
                    (s?["name"] ?? "MIGUEL ANGEL\nGONZALEZ POSADA")
                        .toString()
                        .toUpperCase(),
                    style: const TextStyle(
                      color: grisTexto,
                      fontSize: 18,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // CÓDIGO / VENCE
                  Row(
                    children: const [
                      Expanded(child: _Label("CÓDIGO")),
                      SizedBox(width: 6),
                      Expanded(child: _Label("VENCE")),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s?["code"] ?? s?["id"] ?? "430075236",
                          style: const TextStyle(
                            color: grisTexto,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s?["expiresAt"] ?? "30/06/2025",
                          style: const TextStyle(
                            color: grisTexto,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // PROGRAMA
                  const _Label("PROGRAMA"),
                  Text(
                    (s?["program"] ?? "INGENIERIA DE SISTEMAS")
                        .toString()
                        .toUpperCase(),
                    style: const TextStyle(
                      color: grisTexto,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // BANDA ROJA ESTUDIANTE
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 14,
                    ),
                    decoration: BoxDecoration(
                      color: rojoMarca,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text(
                        "ESTUDIANTE",
                        style: TextStyle(
                          color: Colors.white,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Leyenda de expiración (fuera de la tarjeta)
            Column(
              children: [
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(fontFamily: 'Roboto'),
                    children: [
                      const TextSpan(
                        text: "CODIGO QR\n",
                        style: TextStyle(
                          color: Color(0xFFB0191D),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const TextSpan(
                        text: "EXPIRA EN ",
                        style: TextStyle(
                          color: Color(0xFFB0191D),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                      TextSpan(
                        text: "${_secondsLeft.clamp(0, 999)} s",
                        style: const TextStyle(
                          color: Color(0xFFB0191D),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Se renueva automáticamente",
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8), fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 10),

            OutlinedButton(
              onPressed: _fetchQr,
              child: const Text("Generar ahora"),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Widgets auxiliares ----------

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        letterSpacing: 1.4,
        fontSize: 11,
        color: Colors.black54,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _FotoBox extends StatelessWidget {
  final String? photoUrl; // si en el futuro viene del backend
  final String photoAssetPath; // fallback local
  final double width;
  final double height;

  const _FotoBox({
    required this.photoAssetPath,
    this.photoUrl,
    this.width = 150,
    this.height = 175,
  });

  @override
  Widget build(BuildContext context) {
    Image img;
    bool looksLikeUrl(String s) => s.startsWith('http://') || s.startsWith('https://') || s.startsWith('data:image');
    if (photoUrl != null && photoUrl!.isNotEmpty && looksLikeUrl(photoUrl!)) {
      if (photoUrl!.startsWith('data:image')) {
        final b64 = photoUrl!.split(',').last;
        img = Image.memory(base64Decode(b64), fit: BoxFit.cover);
      } else {
        img = Image.network(photoUrl!, fit: BoxFit.cover);
      }
    } else {
      img = Image.asset(photoAssetPath, fit: BoxFit.cover);
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E6E6)),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black12)],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: img),
    );
  }
}

class _QrGrande extends StatelessWidget {
  final String? qrUrl;
  final double size;
  const _QrGrande({this.qrUrl, this.size = 230});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(blurRadius: 6, color: Colors.black.withOpacity(0.08)),
        ],
      ),
      child: qrUrl == null
          ? const Center(child: CircularProgressIndicator())
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.98, end: 1).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                  child: child,
                ),
              ),
              child: QrImageView(
                key: ValueKey(qrUrl),
                data: qrUrl!,
                version: QrVersions.auto,
                size: size - 12, // ocupa casi todo el contenedor
                backgroundColor: Colors.white,
                // foregroundColor default es negro para buen contraste
              ),
            ),
    );
  }
}
