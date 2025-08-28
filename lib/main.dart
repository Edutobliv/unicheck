import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      routes: {
        '/carnet': (_) => const CarnetPage(),
        '/login': (_) => const LoginPage(),
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
  final String _baseUrl = "http://10.0.2.2:3000"; // backend local en emulador

  String? _qrUrl;
  int _secondsLeft = 0;
  Timer? _timer;
  Map<String, dynamic>? _student;

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
    _fetchQr();
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
        });
        _startCountdown();
      } else {
        _toast("No se pudo generar el QR (${resp.statusCode})");
      }
    } catch (e) {
      _toast("Error de red: $e");
    }
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
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    final s = _student;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Carnet Digital"),
        actions: [
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
                          child: _QrGrande(qrUrl: _qrUrl, size: kQrSize),
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
                          s?["id"] ?? "430075236",
                          style: const TextStyle(
                            color: grisTexto,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          "30/06/2025",
                          style: TextStyle(
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
                const Text(
                  "Se renueva automáticamente",
                  style: TextStyle(color: Colors.black54, fontSize: 13),
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
    final img = (photoUrl != null && photoUrl!.isNotEmpty)
        ? Image.network(photoUrl!, fit: BoxFit.cover)
        : Image.asset(photoAssetPath, fit: BoxFit.cover);

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E6E6)),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black12)],
      ),
      child: qrUrl == null
          ? const Center(child: CircularProgressIndicator())
          : QrImageView(
              data: qrUrl!,
              version: QrVersions.auto,
              size: size - 12, // ocupa casi todo el contenedor
            ),
    );
  }
}
