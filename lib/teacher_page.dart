import 'dart:async';
import 'dart:convert';
import 'dart:ui';
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
    text: '60',
  );
  String? _sessionId;
  String? _qrText;
  int? _expiresAt;
  int? _startedAt;
  List<Map<String, dynamic>> _attendees = [];
  Timer? _pollTimer;
  Timer? _elapsedTicker;

  // Sugerencias y alta manual
  final TextEditingController _addController = TextEditingController();
  List<Map<String, String>> _suggestions = [];
  Timer? _debounce;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _elapsedTicker?.cancel();
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

  String? _startTimeLabel() {
    final s = _startedAt;
    if (s == null) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(s * 1000).toLocal();
    return 'Inicio: ${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
  }

  String _elapsedLabel() {
    final s = _startedAt;
    if (s == null) return '';
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var effectiveNow = nowSeconds;
    final exp = _expiresAt;
    if (exp != null && exp < effectiveNow) {
      effectiveNow = exp;
    }
    final diff = effectiveNow - s;
    final safeDiff = diff < 0 ? 0 : diff;
    final hours = safeDiff ~/ 3600;
    final minutes = (safeDiff % 3600) ~/ 60;
    final seconds = safeDiff % 60;
    return '${_two(hours)}:${_two(minutes)}:${_two(seconds)}';
  }

  void _scheduleElapsedTicker() {
    _elapsedTicker?.cancel();
    final start = _startedAt;
    if (start == null) return;
    final exp = _expiresAt;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (exp != null && exp <= now) {
      return;
    }
    _elapsedTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final currentExp = _expiresAt;
      final currentNow = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (currentExp != null && currentExp <= currentNow) {
        setState(() {});
        timer.cancel();
      } else {
        setState(() {});
      }
    });
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
        final startedAt = session['startedAt'] as int?;
        setState(() {
          _sessionId = session['id'] as String;
          _expiresAt = session['expiresAt'] as int?;
          _startedAt = startedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
          _qrText = data['qrText'] as String;
          _attendees = [];
        });
        _startPolling();
        _scheduleElapsedTicker();
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
        _elapsedTicker?.cancel();
        setState(() {
          _sessionId = null;
          _qrText = null;
          _startedAt = null;
          _expiresAt = null;
          _attendees = [];
          _addController.clear();
          _suggestions = [];
        });
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
        final session = (data['session'] as Map).cast<String, dynamic>();
        setState(() {
          _attendees = list;
          _startedAt = session['startedAt'] as int?;
          _expiresAt = session['expiresAt'] as int?;
        });
        _scheduleElapsedTicker();
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
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final double qrSize = (screenWidth - 16 * 2 - 24 * 2).clamp(180.0, 300.0);
    final bool activeSession =
        _sessionId != null && _qrText != null && _startedAt != null;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.15),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: SingleChildScrollView(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: activeSession
                        ? _ActiveSessionView(
                            key: const ValueKey('active'),
                            startLabel: _startTimeLabel() ?? 'Inicio',
                            elapsedLabel: _elapsedLabel(),
                            onFinish: () {
                              _endSession();
                            },
                            expiryLabel: _expiryLabel(),
                            qrText: _qrText!,
                            qrSize: qrSize,
                            addController: _addController,
                            onAddAttendee: () {
                              _addAttendee();
                            },
                            onQueryChange: _handleQueryChange,
                            suggestions: _suggestions,
                            onSuggestionTap: _onSuggestionTap,
                            attendees: _attendees,
                            onRemoveAttendee: _removeAttendee,
                            confirmDelete: _confirmDelete,
                            logout: () {
                              _logout();
                            },
                          )
                        : _PreSessionView(
                            key: const ValueKey('pre'),
                            durationController: _durationController,
                            onStart: () {
                              _startSession();
                            },
                            logout: () {
                              _logout();
                            },
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleQueryChange(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (RegExp(r'^\d').hasMatch(trimmed)) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () {
        if (trimmed.isNotEmpty) _searchSuggestions(trimmed);
      },
    );
  }

  void _onSuggestionTap(Map<String, String> suggestion) {
    _addController.text = suggestion['email']!;
    setState(() => _suggestions = []);
  }
}

class _PreSessionView extends StatelessWidget {
  const _PreSessionView({
    super.key,
    required this.durationController,
    required this.onStart,
    required this.logout,
  });

  final TextEditingController durationController;
  final VoidCallback onStart;
  final VoidCallback logout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(logout: logout),
        const SizedBox(height: 24),
        Text(
          'Duración (minutos)',
          style: theme.textTheme.labelLarge?.copyWith(
            letterSpacing: 0.2,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: durationController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: '60',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text(
              'Iniciar sesión de clase',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActiveSessionView extends StatelessWidget {
  const _ActiveSessionView({
    super.key,
    required this.startLabel,
    required this.elapsedLabel,
    required this.onFinish,
    required this.expiryLabel,
    required this.qrText,
    required this.qrSize,
    required this.addController,
    required this.onAddAttendee,
    required this.onQueryChange,
    required this.suggestions,
    required this.onSuggestionTap,
    required this.attendees,
    required this.onRemoveAttendee,
    required this.confirmDelete,
    required this.logout,
  });

  final String startLabel;
  final String elapsedLabel;
  final VoidCallback onFinish;
  final String expiryLabel;
  final String qrText;
  final double qrSize;
  final TextEditingController addController;
  final VoidCallback onAddAttendee;
  final ValueChanged<String> onQueryChange;
  final List<Map<String, String>> suggestions;
  final ValueChanged<Map<String, String>> onSuggestionTap;
  final List<Map<String, dynamic>> attendees;
  final Future<void> Function(String, {String? label}) onRemoveAttendee;
  final Future<bool> Function(String) confirmDelete;
  final VoidCallback logout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(logout: logout),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _InfoCard(
                title: startLabel,
                subtitle: 'Tiempo transcurrido',
                value: elapsedLabel,
                background: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                valueStyle: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _InfoCard(
                title: expiryLabel.isEmpty ? 'Expira' : expiryLabel,
                subtitle: '',
                value: '',
                background: Colors.red.shade50,
                borderColor: Colors.red.shade200,
                titleStyle: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onFinish,
            icon: const Icon(Icons.stop_rounded),
            label: const Text(
              'Finalizar sesión',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(
                    data: qrText,
                    version: QrVersions.auto,
                    size: qrSize,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'CÓDIGO',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                qrText,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Añadir por código o cédula',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: addController,
                decoration: const InputDecoration(
                  hintText: 'Código o cédula...',
                  border: OutlineInputBorder(),
                ),
                onChanged: onQueryChange,
                onSubmitted: (_) => onAddAttendee(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onAddAttendee,
              child: const Text('Añadir'),
            ),
          ],
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.separated(
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final suggestion = suggestions[index];
                return ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    suggestion['name']!.isNotEmpty
                        ? suggestion['name']!
                        : suggestion['email']!,
                  ),
                  subtitle:
                      Text('${suggestion['email']} - ${suggestion['code']}'),
                  onTap: () => onSuggestionTap(suggestion),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 28),
        Text(
          'Asistentes: ${attendees.length}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: attendees.isEmpty
              ? Text(
                  'Aún no hay asistentes.',
                  style: theme.textTheme.bodyMedium,
                )
              : ListView.separated(
                  key: ValueKey(attendees.length),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: attendees.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, index) {
                    final attendee = attendees[index];
                    final when = attendee['at'] is int
                        ? DateTime.fromMillisecondsSinceEpoch(
                            (attendee['at'] as int) * 1000,
                          )
                        : null;
                    final label =
                        (attendee['name'] ?? attendee['code'] ?? 'Estudiante')
                            .toString();
                    final code = (attendee['code'] ?? '').toString();
                    return Dismissible(
                      key: ValueKey(code.isNotEmpty ? code : index),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) async {
                        final ok = await confirmDelete(label);
                        if (ok && code.isNotEmpty) {
                          await onRemoveAttendee(code, label: label);
                        }
                        return ok;
                      },
                      background: Container(
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                      ),
                      child: Material(
                        elevation: 1,
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          title: Text(label),
                          subtitle: Text(
                            '${attendee['email'] ?? ''}${when != null ? ' · ${when.toLocal()}' : ''}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Eliminar',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final ok = await confirmDelete(label);
                              if (ok && code.isNotEmpty) {
                                await onRemoveAttendee(code, label: label);
                              }
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.subtitle,
    required this.value,
    this.background,
    this.borderColor,
    this.titleStyle,
    this.valueStyle,
  });

  final String title;
  final String subtitle;
  final String value;
  final Color? background;
  final Color? borderColor;
  final TextStyle? titleStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: borderColor != null ? Border.all(color: borderColor!) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: titleStyle ??
                theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (value.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              value,
              style: valueStyle ??
                  theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.logout});

  final VoidCallback logout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Panel del Profesor',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Cerrar sesión',
          onPressed: logout,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}
