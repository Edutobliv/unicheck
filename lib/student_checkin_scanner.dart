import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudentCheckInScanner extends StatefulWidget {
  const StudentCheckInScanner({super.key});

  @override
  State<StudentCheckInScanner> createState() => _StudentCheckInScannerState();
}

class _StudentCheckInScannerState extends State<StudentCheckInScanner> {
  final String _baseUrl = "http://10.0.2.2:3000";
  bool _handled = false;

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_handled) return;
    final codes = capture.barcodes;
    if (codes.isEmpty) return;
    final raw = codes.first.rawValue;
    if (raw == null) return;
    String token;
    if (raw.startsWith('ATTEND:')) {
      token = raw.substring('ATTEND:'.length);
    } else {
      // Permitimos pegar el JWT directo en el QR
      token = raw;
    }
    setState(() => _handled = true);
    await _checkIn(token);
  }

  Future<void> _checkIn(String sessionToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final auth = prefs.getString('token');
      if (auth == null) throw Exception('No autenticado');
      final resp = await http.post(
        Uri.parse("$_baseUrl/attendance/check-in"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $auth",
        },
        body: jsonEncode({
          "sessionToken": sessionToken,
        }),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final already = data['already'] == true;
        final msg = already
            ? 'Asistencia ya registrada.'
            : 'Asistencia registrada correctamente.';
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Check-in'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              )
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop();
      } else {
        final msg = 'Error (${resp.statusCode}): ${resp.body}';
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Error de check-in'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              )
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Error'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            )
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear QR de Asistencia'),
        actions: const [ThemeToggleButton()],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
          Positioned.fill(
            child: Opacity(
              opacity: 0.85,
              child: MobileScanner(onDetect: _handleBarcode),
            ),
          ),
          // Overlay con recorte para guía de escaneo
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ScannerOverlayPainter(color: Colors.white.withOpacity(0.85))),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Color color;
  _ScannerOverlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final cutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.7,
      height: size.width * 0.7,
    );
    final rrect = RRect.fromRectAndRadius(cutRect, const Radius.circular(16));

    // Fondo oscuro
    canvas.drawRect(Offset.zero & size, paint);

    // Recorte del centro
    final clearPaint = Paint()
      ..blendMode = BlendMode.clear;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, paint);
    canvas.drawRRect(rrect, clearPaint);
    canvas.restore();

    // Bordes de guía
    final guidePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(rrect, guidePaint);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) => oldDelegate.color != color;
}
