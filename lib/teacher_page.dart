import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'api_config.dart';

class TeacherPage extends StatefulWidget {
  const TeacherPage({super.key});

  @override
  State<TeacherPage> createState() => _TeacherPageState();
}

class _TeacherPageState extends State<TeacherPage> {
  final String _baseUrl = ApiConfig.baseUrl;
  final _durationController = TextEditingController(text: '10'); // minutos
  String? _sessionId;
  String? _qrText;
  int? _expiresAt;
  int? _startedAt;
  List<Map<String, dynamic>> _attendees = [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _durationController.dispose();
    super.dispose();
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> _startSession() async {
    try {
      final token = await _token();
      if (token == null) return;
      final minutes = int.tryParse(_durationController.text.trim());
      final ttlSeconds = (minutes != null && minutes > 0) ? minutes * 60 : 600;
      final resp = await http.post(
        Uri.parse("$_baseUrl/prof/start-session"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "ttlSeconds": ttlSeconds,
        }),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _sessionId = (data['session'] as Map)['id'] as String;
          _startedAt = (data['session'] as Map)['startedAt'] as int?;
          _expiresAt = (data['session'] as Map)['expiresAt'] as int?;
          _qrText = data['qrText'] as String;
          _attendees = [];
        });
        _startPolling();
      } else {
        _toast('No se pudo iniciar la sesión (${resp.statusCode})');
      }
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _endSession() async {
    final id = _sessionId;
    if (id == null) return;
    try {
      final token = await _token();
      if (token == null) return;
      final resp = await http.post(
        Uri.parse("$_baseUrl/prof/end-session"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "sessionId": id,
        }),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _expiresAt = (data['session'] as Map)['expiresAt'] as int?;
        });
        _pollTimer?.cancel();
        await _fetchAttendance();
      } else {
        _toast('No se pudo finalizar (${resp.statusCode})');
      }
    } catch (e) {
      _toast('Error: $e');
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchAttendance());
  }

  Future<void> _fetchAttendance() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    try {
      final token = await _token();
      if (token == null) return;
      final resp = await http.get(
        Uri.parse("$_baseUrl/prof/session/$sessionId"),
        headers: {
          "Authorization": "Bearer $token",
        },
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = (data['attendees'] as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
        setState(() {
          _attendees = list;
          _expiresAt = (data['session'] as Map)['expiresAt'] as int?;
        });
      }
    } catch (_) {}
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel del Profesor'),
        actions: [
          const ThemeToggleButton(),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duración (min)',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _startSession,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar sesión de clase'),
                ),
                const SizedBox(width: 12),
                if (_sessionId != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600),
                    onPressed: _endSession,
                    icon: const Icon(Icons.stop),
                    label: const Text('Finalizar sesión'),
                  ),
                const SizedBox(width: 12),
                if (_expiresAt != null)
                  Text('Expira: ${DateTime.fromMillisecondsSinceEpoch((_expiresAt!)*1000)}'),
              ],
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.98, end: 1).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                  child: child,
                ),
              ),
              child: _qrText != null
                  ? Center(
                      key: const ValueKey('qr'),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: QrImageView(
                            data: _qrText!,
                            version: QrVersions.auto,
                            size: 220,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    )
                  : const Text('Inicia una sesión para generar el QR.'),
            ),
            const SizedBox(height: 16),
            const Text('Asistentes:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _attendees.isEmpty
                    ? const Text('Aún no hay asistentes.')
                    : ListView.separated(
                        key: ValueKey(_attendees.length),
                        itemBuilder: (_, i) {
                          final a = _attendees[i];
                          final when = a['at'] is int
                              ? DateTime.fromMillisecondsSinceEpoch((a['at'] as int) * 1000)
                              : null;
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(a['name'] ?? a['code'] ?? 'Estudiante'),
                              subtitle: Text('${a['email'] ?? ''}${when != null ? ' • ${when.toLocal()}' : ''}'),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemCount: _attendees.length,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
