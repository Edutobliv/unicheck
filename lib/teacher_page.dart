import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

class TeacherPage extends StatefulWidget {
  const TeacherPage({super.key});
  @override
  State<TeacherPage> createState() => _TeacherPageState();
}

class _TeacherPageState extends State<TeacherPage> {
  final String _baseUrl = ApiConfig.baseUrl;

  final TextEditingController _durationController = TextEditingController(
    text: '10',
  );
  String? _sessionId;
  String? _qrText;
  int? _expiresAt;
  List<Map<String, dynamic>> _attendees = [];
  Timer? _pollTimer;

  // Sugerencias y alta manual
  final TextEditingController _addController = TextEditingController();
  List<Map<String, String>> _suggestions = [];
  Timer? _debounce;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _debounce?.cancel();
    _durationController.dispose();
    _addController.dispose();
    super.dispose();
  }

  String _two(int v) => v.toString().padLeft(2, '0');
  String _expiryLabel() {
    final e = _expiresAt;
    if (e == null) return '';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (e <= now) return 'Expirada';
    final dt = DateTime.fromMillisecondsSinceEpoch(e * 1000).toLocal();
    return 'Expira: ${_two(dt.hour)}:${_two(dt.minute)}';
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _startSession() async {
    try {
      final token = await _token();
      if (token == null) return;
      final minutes = int.tryParse(_durationController.text.trim());
      final ttlSeconds = (minutes != null && minutes > 0) ? minutes * 60 : 600;
      final resp = await http.post(
        Uri.parse('$_baseUrl/prof/start-session'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'ttlSeconds': ttlSeconds}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final session = (data['session'] as Map).cast<String, dynamic>();
        setState(() {
          _sessionId = session['id'] as String;
          _expiresAt = session['expiresAt'] as int?;
          _qrText = data['qrText'] as String;
          _attendees = [];
        });
        _startPolling();
      } else {
        _toast('No se pudo iniciar la sesion (${resp.statusCode})');
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
        Uri.parse('$_baseUrl/prof/end-session'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'sessionId': id}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final session = (data['session'] as Map).cast<String, dynamic>();
        setState(() {
          _expiresAt = session['expiresAt'] as int?;
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
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _fetchAttendance(),
    );
  }

  Future<void> _fetchAttendance() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    try {
      final token = await _token();
      if (token == null) return;
      final resp = await http.get(
        Uri.parse('$_baseUrl/prof/session/$sessionId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = (data['attendees'] as List)
            .cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        setState(() {
          _attendees = list;
          _expiresAt = (data['session'] as Map)['expiresAt'] as int?;
        });
      }
    } catch (_) {}
  }

  Future<void> _removeAttendee(String studentCode, {String? label}) async {
    final id = _sessionId;
    if (id == null) return;
    try {
      final token = await _token();
      if (token == null) return;
      final resp = await http.delete(
        Uri.parse('$_baseUrl/prof/attendance'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'sessionId': id, 'studentCode': studentCode}),
      );
      if (resp.statusCode == 200) {
        // Actualiza lista y ofrece Undo
        await _fetchAttendance();
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Eliminado ${label ?? studentCode}'),
            action: SnackBarAction(
              label: 'Deshacer',
              onPressed: () async {
                await _addByCode(studentCode);
              },
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        _toast('No se pudo eliminar (${resp.statusCode})');
      }
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _addByCode(String code) async {
    final id = _sessionId;
    if (id == null) return;
    try {
      final token = await _token();
      if (token == null) return;
      final resp = await http.post(
        Uri.parse('$_baseUrl/prof/attendance/add'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'sessionId': id, 'code': code}),
      );
      if (resp.statusCode == 200) {
        await _fetchAttendance();
      } else {
        _toast('No se pudo deshacer (${resp.statusCode})');
      }
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _addAttendee() async {
    final id = _sessionId;
    if (id == null) {
      _toast('Inicia una sesion primero');
      return;
    }
    final q = _addController.text.trim();
    if (q.isEmpty) return;
    try {
      final token = await _token();
      if (token == null) return;
      final isNumeric = RegExp(r'^\d{4,}$').hasMatch(q);
      final body = isNumeric
          ? {'sessionId': id, 'code': q}
          : {'sessionId': id, 'email': q};
      final resp = await http.post(
        Uri.parse('$_baseUrl/prof/attendance/add'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      if (resp.statusCode == 200) {
        _addController.clear();
        setState(() => _suggestions = []);
        await _fetchAttendance();
      } else if (resp.statusCode == 404) {
        _toast('Estudiante no encontrado');
      } else {
        _toast('No se pudo anadir (${resp.statusCode})');
      }
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _searchSuggestions(String q) async {
    try {
      final token = await _token();
      if (token == null) return;
      final resp = await http.get(
        Uri.parse(
          '$_baseUrl/prof/students/search?q=${Uri.encodeQueryComponent(q)}',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final items = (data['items'] as List)
            .cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        setState(() {
          _suggestions = items
              .map(
                (e) => {
                  'email': (e['email'] ?? '').toString(),
                  'code': (e['code'] ?? '').toString(),
                  'name': (e['name'] ?? '').toString(),
                },
              )
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<bool> _confirmDelete(String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar asistente'),
        content: Text('Eliminar a $label de la sesion?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    return ok ?? false;
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
    final screenWidth = MediaQuery.of(context).size.width;
    // Ajusta el tamaño del QR para pantallas estrechas evitando overflow horizontal
    final double qrSize = (screenWidth - 16 * 2 - 24 * 2).clamp(180.0, 300.0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel del Profesor'),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Usar Wrap en lugar de Row para que los botones salten de línea en pantallas estrechas
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _durationController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Duracion (min)',
                        isDense: true,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _startSession,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Iniciar sesion de clase'),
                  ),
                  if (_sessionId != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                      ),
                      onPressed: _endSession,
                      icon: const Icon(Icons.stop),
                      label: const Text('Finalizar sesion'),
                    ),
                  if (_expiresAt != null)
                    Text(
                      _expiryLabel(),
                      softWrap: false,
                      overflow: TextOverflow.fade,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.98, end: 1).animate(
                      CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                    ),
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
                              size: qrSize,
                              errorCorrectionLevel: QrErrorCorrectLevel.M,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                      )
                    : const Text('Inicia una sesion para generar el QR.'),
              ),
              const SizedBox(height: 16),
              // Añadir asistente manualmente
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addController,
                      decoration: const InputDecoration(
                        labelText:
                            'Añadir por codigo o correo (solo estudiantes)',
                        hintText: 'Ej: 470056402 o juan@upc.edu.co',
                      ),
                      onChanged: (v) {
                        _debounce?.cancel();
                        final s = v.trim();
                        if (RegExp(r'^\d').hasMatch(s)) {
                          setState(() => _suggestions = []);
                          return;
                        }
                        _debounce = Timer(
                          const Duration(milliseconds: 350),
                          () {
                            if (s.isNotEmpty) _searchSuggestions(s);
                          },
                        );
                      },
                      onSubmitted: (_) => _addAttendee(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _addAttendee,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Añadir'),
                  ),
                ],
              ),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.6),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = _suggestions[i];
                      return ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(
                          s['name']!.isNotEmpty ? s['name']! : s['email']!,
                        ),
                        subtitle: Text('${s['email']} - ${s['code']}'),
                        onTap: () {
                          _addController.text = s['email']!;
                          setState(() => _suggestions = []);
                        },
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Asistentes:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _attendees.isEmpty
                    ? const Text('Aun no hay asistentes.')
                    : ListView.separated(
                        key: ValueKey(_attendees.length),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemBuilder: (_, i) {
                          final a = _attendees[i];
                          final when = a['at'] is int
                              ? DateTime.fromMillisecondsSinceEpoch(
                                  (a['at'] as int) * 1000,
                                )
                              : null;
                          final label = (a['name'] ?? a['code'] ?? 'Estudiante')
                              .toString();
                          final code = (a['code'] ?? '').toString();
                          return Dismissible(
                            key: ValueKey(code.isNotEmpty ? code : i),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) async {
                              final ok = await _confirmDelete(label);
                              if (ok && code.isNotEmpty) {
                                await _removeAttendee(code);
                              }
                              return ok;
                            },
                            background: Container(
                              color: Colors.red.shade100,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                            ),
                            child: Card(
                              child: ListTile(
                                leading: const Icon(Icons.person),
                                title: Text(label),
                                subtitle: Text(
                                  '${a['email'] ?? ''}${when != null ? ' - ${when.toLocal()}' : ''}',
                                ),
                                trailing: IconButton(
                                  tooltip: 'Eliminar',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final ok = await _confirmDelete(label);
                                    if (ok && code.isNotEmpty) {
                                      await _removeAttendee(code);
                                    }
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemCount: _attendees.length,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
