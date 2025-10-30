import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'ui_kit.dart';

const _headerGradient = LinearGradient(
  colors: [Color(0xFF1BD8C8), Color(0xFF118AD5)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const _cardBackground = Color(0xFF13233A);
const _tileBackground = Color(0xFF1B2F4A);
const _tileBorder = Color(0x3329F1CF);
const _dangerColor = Color(0xFFE05B69);

class TeacherClass {
  const TeacherClass({
    required this.id,
    required this.name,
    this.sessionsCount = 0,
    this.lastSessionAt,
    this.createdAt,
  });

  final String id;
  final String name;
  final int sessionsCount;
  final int? lastSessionAt;
  final int? createdAt;

  TeacherClass copyWith({
    String? name,
    int? sessionsCount,
    int? lastSessionAt,
    int? createdAt,
  }) {
    return TeacherClass(
      id: id,
      name: name ?? this.name,
      sessionsCount: sessionsCount ?? this.sessionsCount,
      lastSessionAt: lastSessionAt ?? this.lastSessionAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory TeacherClass.fromJson(Map<String, dynamic> json) {
    return TeacherClass(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Clase',
      sessionsCount: (json['sessionsCount'] as num?)?.toInt() ??
          (json['totalSessions'] as num?)?.toInt() ??
          0,
      lastSessionAt: (json['lastSessionAt'] as num?)?.toInt(),
      createdAt: (json['createdAt'] as num?)?.toInt(),
    );
  }
}

class ClassSessionSummary {
  const ClassSessionSummary({
    required this.id,
    this.startedAt,
    this.expiresAt,
    this.attendeeCount = 0,
  });

  final String id;
  final int? startedAt;
  final int? expiresAt;
  final int attendeeCount;

  ClassSessionSummary copyWith({
    int? startedAt,
    int? expiresAt,
    int? attendeeCount,
  }) {
    return ClassSessionSummary(
      id: id,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      attendeeCount: attendeeCount ?? this.attendeeCount,
    );
  }

  factory ClassSessionSummary.fromJson(Map<String, dynamic> json) {
    return ClassSessionSummary(
      id: json['id']?.toString() ?? '',
      startedAt: (json['startedAt'] as num?)?.toInt(),
      expiresAt: (json['expiresAt'] as num?)?.toInt(),
      attendeeCount: (json['attendeeCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class SessionAttendee {
  const SessionAttendee({
    required this.code,
    this.name,
    this.email,
    this.at,
  });

  final String code;
  final String? name;
  final String? email;
  final int? at;

  factory SessionAttendee.fromJson(Map<String, dynamic> json) {
    return SessionAttendee(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString(),
      email: json['email']?.toString(),
      at: (json['at'] as num?)?.toInt(),
    );
  }
}

enum _TeacherView {
  overview,
  createClass,
  configureSession,
  historyClasses,
  historySessions,
  historySessionDetail,
  activeSession,
}

class TeacherPage extends StatefulWidget {
  const TeacherPage({super.key});

  @override
  State<TeacherPage> createState() => _TeacherPageState();
}

class _TeacherPageState extends State<TeacherPage> {
  final String _baseUrl = ApiConfig.baseUrl;

  final TextEditingController _durationController =
      TextEditingController(text: '60');
  final TextEditingController _classNameController = TextEditingController();
  final TextEditingController _addController = TextEditingController();

  final List<TeacherClass> _classes = [];
  bool _loadingClasses = false;
  bool _creatingClass = false;

  _TeacherView _view = _TeacherView.overview;
  TeacherClass? _selectedClass;
  TeacherClass? _activeClass;
  TeacherClass? _historyClass;

  final List<ClassSessionSummary> _historySessions = [];
  bool _loadingHistorySessions = false;
  ClassSessionSummary? _historySelectedSession;
  final List<SessionAttendee> _historyAttendees = [];
  bool _loadingHistoryDetail = false;

  String? _sessionId;
  String? _qrText;
  int? _expiresAt;
  int? _startedAt;
  final List<Map<String, dynamic>> _attendees = [];
  Timer? _pollTimer;
  Timer? _elapsedTicker;

  final List<Map<String, String>> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _elapsedTicker?.cancel();
    _debounce?.cancel();
    _durationController.dispose();
    _classNameController.dispose();
    _addController.dispose();
    super.dispose();
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadClasses() async {
    final token = await _token();
    if (token == null) return;
    setState(() {
      _loadingClasses = true;
    });
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/prof/classes'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final items = (data['items'] as List? ?? [])
            .cast<Map>()
            .map((e) => TeacherClass.fromJson(e.cast<String, dynamic>()))
            .toList();
        if (!mounted) return;
        setState(() {
          _classes
            ..clear()
            ..addAll(items);
        });
      } else {
        _toast('No se pudieron cargar las clases (${resp.statusCode})');
      }
    } catch (e) {
      _toast('Error al cargar clases: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingClasses = false;
        });
      }
    }
  }

  void _goToOverview() {
    setState(() {
      _view = _TeacherView.overview;
      _selectedClass = null;
      _historyClass = null;
      _historySessions.clear();
      _historySelectedSession = null;
      _historyAttendees.clear();
    });
  }

  void _openCreateClass() {
    FocusScope.of(context).unfocus();
    setState(() {
      _classNameController.clear();
      _creatingClass = false;
      _view = _TeacherView.createClass;
    });
  }

  Future<void> _submitClass() async {
    final name = _classNameController.text.trim();
    if (name.length < 3) {
      _toast('Ingresa un nombre valido (minimo 3 caracteres)');
      return;
    }
    final token = await _token();
    if (token == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _creatingClass = true;
    });
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/prof/classes'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'name': name}),
      );
      if (resp.statusCode == 201) {
        _classNameController.clear();
        await _loadClasses();
        if (!mounted) return;
        setState(() {
          _view = _TeacherView.overview;
        });
        _toast('Clase creada');
      } else if (resp.statusCode == 400) {
        try {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final message = body['message']?.toString();
          if (message != null && message.isNotEmpty) {
            _toast(message);
          } else {
            _toast('Nombre invalido');
          }
        } catch (_) {
          _toast('Nombre invalido');
        }
      } else {
        _toast('No se pudo crear la clase (${resp.statusCode})');
      }
    } catch (e) {
      _toast('Error al crear clase: $e');
    } finally {
      if (mounted) {
        setState(() {
          _creatingClass = false;
        });
      }
    }
  }

  void _selectClass(TeacherClass klass) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedClass = klass;
      _view = _TeacherView.configureSession;
    });
  }

  void _openHistory() {
    FocusScope.of(context).unfocus();
    setState(() {
      _view = _TeacherView.historyClasses;
      _historyClass = null;
      _historySessions.clear();
      _historySelectedSession = null;
      _historyAttendees.clear();
    });
  }

  Future<void> _openHistorySessions(TeacherClass klass) async {
    final token = await _token();
    if (token == null) return;
    setState(() {
      _historyClass = klass;
      _historySessions.clear();
      _historySelectedSession = null;
      _historyAttendees.clear();
      _loadingHistorySessions = true;
      _view = _TeacherView.historySessions;
    });
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/prof/classes/${klass.id}/sessions'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final offering = (data['offering'] as Map?)?.cast<String, dynamic>();
        final sessions = (data['sessions'] as List? ?? [])
            .cast<Map>()
            .map((e) => ClassSessionSummary.fromJson(e.cast<String, dynamic>()))
            .toList();
        if (!mounted) return;
        setState(() {
          _historyClass =
              offering != null ? TeacherClass.fromJson(offering) : klass;
          _historySessions
            ..clear()
            ..addAll(sessions);
        });
      } else {
        _toast('No se pudo cargar el historial (${resp.statusCode})');
      }
    } catch (e) {
      _toast('Error al cargar historial: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingHistorySessions = false;
        });
      }
    }
  }

  Future<void> _openSessionDetail(ClassSessionSummary summary) async {
    final token = await _token();
    if (token == null) return;
    setState(() {
      _historySelectedSession = summary;
      _historyAttendees.clear();
      _loadingHistoryDetail = true;
      _view = _TeacherView.historySessionDetail;
    });
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/prof/session/${summary.id}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final session = (data['session'] as Map?)?.cast<String, dynamic>();
        final attendees = (data['attendees'] as List? ?? [])
            .cast<Map>()
            .map((e) => SessionAttendee.fromJson(e.cast<String, dynamic>()))
            .toList();
        if (!mounted) return;
        setState(() {
          if (session != null) {
            _historySelectedSession = summary.copyWith(
              startedAt: (session['startedAt'] as num?)?.toInt(),
              expiresAt: (session['expiresAt'] as num?)?.toInt(),
              attendeeCount: attendees.length,
            );
          } else {
            _historySelectedSession = summary.copyWith(
              attendeeCount: attendees.length,
            );
          }
          _historyAttendees
            ..clear()
            ..addAll(attendees);
        });
      } else {
        _toast('No se pudo obtener la sesion (${resp.statusCode})');
      }
    } catch (e) {
      _toast('Error al cargar la sesion: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingHistoryDetail = false;
        });
      }
    }
  }

  String? _startTimeLabel() {
    final s = _startedAt;
    if (s == null) return null;
    final dt =
        DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: false).toLocal();
    return '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
  }

  String _expiryDisplay() {
    final e = _expiresAt;
    if (e == null) return '--:--';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (e <= now) return 'Expirada';
    final dt =
        DateTime.fromMillisecondsSinceEpoch(e * 1000, isUtc: false).toLocal();
    return '${_two(dt.hour)}:${_two(dt.minute)}';
  }

  String _elapsedLabel() {
    final s = _startedAt;
    if (s == null) return '00:00:00';
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

  Future<void> _startSession() async {
    final klass = _selectedClass;
    if (klass == null) {
      _toast('Selecciona una clase');
      return;
    }
    final token = await _token();
    if (token == null) return;
    FocusScope.of(context).unfocus();
    try {
      final minutes = int.tryParse(_durationController.text.trim());
      final ttlSeconds = (minutes != null && minutes > 0) ? minutes * 60 : 600;
      final resp = await http.post(
        Uri.parse('$_baseUrl/prof/start-session'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'ttlSeconds': ttlSeconds,
          'offeringId': klass.id,
        }),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final session = (data['session'] as Map).cast<String, dynamic>();
        final startedAt = session['startedAt'] as int?;
        if (!mounted) return;
        setState(() {
          _sessionId = session['id'] as String;
          _expiresAt = session['expiresAt'] as int?;
          _startedAt = startedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
          _qrText = data['qrText'] as String;
          _attendees.clear();
          _activeClass = klass;
          _view = _TeacherView.activeSession;
        });
        _startPolling();
        _scheduleElapsedTicker();
      } else if (resp.statusCode == 404) {
        _toast('Clase no encontrada');
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
    final token = await _token();
    if (token == null) return;
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/prof/end-session'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'sessionId': id}),
      );
      if (resp.statusCode == 200) {
        _pollTimer?.cancel();
        _elapsedTicker?.cancel();
        if (!mounted) return;
        setState(() {
          _sessionId = null;
          _qrText = null;
          _startedAt = null;
          _expiresAt = null;
          _attendees.clear();
          _addController.clear();
          _suggestions.clear();
          _activeClass = _selectedClass;
          _view = _TeacherView.configureSession;
        });
        await _loadClasses();
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
    final token = await _token();
    if (token == null) return;
    try {
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
        final offeringId = session['offeringId'] as String?;
        TeacherClass? activeClass = _activeClass;
        if (offeringId != null) {
          activeClass = _classes
              .where((c) => c.id == offeringId)
              .fold<TeacherClass?>(activeClass, (prev, element) => element);
        }
        if (!mounted) return;
        setState(() {
          _attendees
            ..clear()
            ..addAll(list);
          _startedAt = session['startedAt'] as int?;
          _expiresAt = session['expiresAt'] as int?;
          _activeClass = activeClass ?? _activeClass;
        });
        _scheduleElapsedTicker();
      }
    } catch (_) {}
  }

  Future<void> _removeAttendee(String studentCode, {String? label}) async {
    final id = _sessionId;
    if (id == null) return;
    final token = await _token();
    if (token == null) return;
    try {
      final resp = await http.delete(
        Uri.parse('$_baseUrl/prof/attendance'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'sessionId': id, 'studentCode': studentCode}),
      );
      if (resp.statusCode == 200) {
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
    final token = await _token();
    if (token == null) return;
    try {
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
    final token = await _token();
    if (token == null) return;
    try {
      final isNumeric = int.tryParse(q) != null && q.length >= 4;
      final body =
          isNumeric ? {'sessionId': id, 'code': q} : {'sessionId': id, 'email': q};
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
        setState(() => _suggestions.clear());
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
    final token = await _token();
    if (token == null) return;
    try {
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
        if (!mounted) return;
        setState(() {
          _suggestions
            ..clear()
            ..addAll(items
                .map(
                  (e) => {
                    'email': (e['email'] ?? '').toString(),
                    'code': (e['code'] ?? '').toString(),
                    'name': (e['name'] ?? '').toString(),
                  },
                )
                .toList());
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

  void _handleQueryChange(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && int.tryParse(trimmed[0]) != null) {
      setState(() => _suggestions.clear());
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
    setState(() => _suggestions.clear());
  }

  String _formatDate(int? seconds) {
    if (seconds == null) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
    return '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';
  }

  String _formatTime(int? seconds) {
    if (seconds == null) return '--:--';
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
    return '${_two(dt.hour)}:${_two(dt.minute)}';
  }

  String _formatDuration(int? start, int? end) {
    if (start == null || end == null) return '--';
    final diff = end - start;
    if (diff <= 0) return '0 min';
    final minutes = (diff / 60).round();
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final qrSize = (screenWidth - 120).clamp(180.0, 320.0);
    final hasActiveSession =
        _sessionId != null && _qrText != null && _startedAt != null;
    final view = hasActiveSession ? _TeacherView.activeSession : _view;

    Widget content;
    switch (view) {
      case _TeacherView.overview:
        content = _OverviewView(
          classes: _classes,
          loading: _loadingClasses,
          onCreateClass: _openCreateClass,
          onViewHistory: _openHistory,
          onSelectClass: _selectClass,
          onLogout: _logout,
        );
        break;
      case _TeacherView.createClass:
        content = _CreateClassView(
          controller: _classNameController,
          submitting: _creatingClass,
          onSubmit: _submitClass,
          onCancel: _goToOverview,
          onLogout: _logout,
        );
        break;
      case _TeacherView.configureSession:
        content = _SessionConfigView(
          klass: _selectedClass,
          durationController: _durationController,
          onStart: _startSession,
          onBack: _goToOverview,
          onLogout: _logout,
        );
        break;
      case _TeacherView.historyClasses:
        content = _HistoryClassesView(
          classes: _classes,
          loading: _loadingClasses,
          onBack: _goToOverview,
          onSelect: _openHistorySessions,
          onLogout: _logout,
        );
        break;
      case _TeacherView.historySessions:
        content = _HistorySessionsView(
          klass: _historyClass,
          sessions: _historySessions,
          loading: _loadingHistorySessions,
          onBack: () {
            setState(() {
              _view = _TeacherView.historyClasses;
            });
          },
          onSelect: _openSessionDetail,
          onLogout: _logout,
          formatDate: _formatDate,
          formatTime: _formatTime,
          formatDuration: (summary) =>
              _formatDuration(summary.startedAt, summary.expiresAt),
        );
        break;
      case _TeacherView.historySessionDetail:
        content = _HistorySessionDetailView(
          klass: _historyClass,
          session: _historySelectedSession,
          attendees: _historyAttendees,
          loading: _loadingHistoryDetail,
          dateLabel: _formatDate(_historySelectedSession?.startedAt),
          startLabel: _formatTime(_historySelectedSession?.startedAt),
          durationLabel: _formatDuration(
              _historySelectedSession?.startedAt,
              _historySelectedSession?.expiresAt),
          onBack: () {
            setState(() {
              _view = _TeacherView.historySessions;
            });
          },
          onLogout: _logout,
        );
        break;
      case _TeacherView.activeSession:
        content = _ActiveSessionView(
          klass: _activeClass,
          startLabel: _startTimeLabel() ?? '--:--:--',
          elapsedLabel: _elapsedLabel(),
          expiryLabel: _expiryDisplay(),
          qrText: _qrText ?? '',
          qrSize: qrSize,
          addController: _addController,
          onAddAttendee: _addAttendee,
          onQueryChange: _handleQueryChange,
          suggestions: List<Map<String, String>>.from(_suggestions),
          onSuggestionTap: _onSuggestionTap,
          attendees: List<Map<String, dynamic>>.from(_attendees),
          onRemoveAttendee: _removeAttendee,
          confirmDelete: _confirmDelete,
          onFinish: _endSession,
          onLogout: _logout,
        );
        break;
    }

    final viewKey = '${view.index}-${_sessionId ?? ''}';
    final horizontalPadding = screenWidth < 380 ? 16.0 : 24.0;

    return BrandScaffold(
      heroBackground: true,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screenWidth < 520 ? screenWidth : 640,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: SingleChildScrollView(
              key: ValueKey(viewKey),
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewView extends StatelessWidget {
  const _OverviewView({
    required this.classes,
    required this.loading,
    required this.onCreateClass,
    required this.onViewHistory,
    required this.onSelectClass,
    required this.onLogout,
  });

  final List<TeacherClass> classes;
  final bool loading;
  final VoidCallback onCreateClass;
  final VoidCallback onViewHistory;
  final ValueChanged<TeacherClass> onSelectClass;
  final VoidCallback onLogout;

  String _sessionsLabel(int count) {
    if (count == 1) return '1 sesión';
    return '$count sesiones';
  }

  @override
  Widget build(BuildContext context) {
    return _TeacherCard(
      icon: Icons.menu_book_rounded,
      title: 'Mis Clases',
      subtitle: 'Gestiona tus asistencias',
      actions: [
        _HeaderIconButton(
          icon: Icons.logout_rounded,
          onTap: onLogout,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  expand: true,
                  onPressed: onViewHistory,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_rounded),
                      SizedBox(width: 8),
                      Text('Ver Historial'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  expand: true,
                  onPressed: onCreateClass,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Nueva Clase'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Selecciona una clase para iniciar sesión:',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          if (loading)
            SizedBox(
              height: 160,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
            )
          else if (classes.isEmpty)
            Text(
              'Aún no tienes clases creadas. Crea una para comenzar.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            )
          else ...[
            for (final klass in classes) ...[
              _ClassTile(
                title: klass.name,
                subtitle: _sessionsLabel(klass.sessionsCount),
                onTap: () => onSelectClass(klass),
              ),
              const SizedBox(height: 12),
            ]
          ],
        ],
      ),
    );
  }
}

class _CreateClassView extends StatelessWidget {
  const _CreateClassView({
    required this.controller,
    required this.submitting,
    required this.onSubmit,
    required this.onCancel,
    required this.onLogout,
  });

  final TextEditingController controller;
  final bool submitting;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return _TeacherCard(
      icon: Icons.menu_book_rounded,
      title: 'Mis Clases',
      subtitle: 'Crear nueva clase',
      actions: [
        _HeaderIconButton(
          icon: Icons.logout_rounded,
          onTap: onLogout,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nombre de la clase',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Ej: Matemáticas 101',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide(color: Color(0xFF4CC4FF)),
              ),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  expand: true,
                  onPressed: submitting ? null : onCancel,
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  expand: true,
                  onPressed: submitting ? null : onSubmit,
                  child: submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Crear'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionConfigView extends StatelessWidget {
  const _SessionConfigView({
    required this.klass,
    required this.durationController,
    required this.onStart,
    required this.onBack,
    required this.onLogout,
  });

  final TeacherClass? klass;
  final TextEditingController durationController;
  final VoidCallback onStart;
  final VoidCallback onBack;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return _TeacherCard(
      icon: Icons.play_circle_outline,
      title: klass?.name ?? 'Configurar sesión',
      subtitle: 'Configurar nueva sesión',
      onBack: onBack,
      actions: [
        _HeaderIconButton(
          icon: Icons.logout_rounded,
          onTap: onLogout,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Duración (minutos)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: durationController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '60',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide(color: Color(0xFF4CC4FF)),
              ),
            ),
          ),
          const SizedBox(height: 28),
          PrimaryButton(
            onPressed: onStart,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text('Iniciar sesión de clase'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryClassesView extends StatelessWidget {
  const _HistoryClassesView({
    required this.classes,
    required this.loading,
    required this.onBack,
    required this.onSelect,
    required this.onLogout,
  });

  final List<TeacherClass> classes;
  final bool loading;
  final VoidCallback onBack;
  final ValueChanged<TeacherClass> onSelect;
  final VoidCallback onLogout;

  String _sessionsLabel(int count) {
    if (count == 1) return '1 sesión registrada';
    return '$count sesiones registradas';
  }

  @override
  Widget build(BuildContext context) {
    return _TeacherCard(
      icon: Icons.history_rounded,
      title: 'Historial de Clases',
      subtitle: 'Consulta las sesiones anteriores',
      onBack: onBack,
      actions: [
        _HeaderIconButton(
          icon: Icons.logout_rounded,
          onTap: onLogout,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading)
            SizedBox(
              height: 160,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
            )
          else if (classes.isEmpty)
            Text(
              'Aún no hay clases con sesiones registradas.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            )
          else ...[
            for (final klass in classes) ...[
              _ClassTile(
                title: klass.name,
                subtitle: _sessionsLabel(klass.sessionsCount),
                onTap: () => onSelect(klass),
              ),
              const SizedBox(height: 12),
            ]
          ],
        ],
      ),
    );
  }
}

class _HistorySessionsView extends StatelessWidget {
  const _HistorySessionsView({
    required this.klass,
    required this.sessions,
    required this.loading,
    required this.onBack,
    required this.onSelect,
    required this.onLogout,
    required this.formatDate,
    required this.formatTime,
    required this.formatDuration,
  });

  final TeacherClass? klass;
  final List<ClassSessionSummary> sessions;
  final bool loading;
  final VoidCallback onBack;
  final ValueChanged<ClassSessionSummary> onSelect;
  final VoidCallback onLogout;
  final String Function(int?) formatDate;
  final String Function(int?) formatTime;
  final String Function(ClassSessionSummary) formatDuration;

  @override
  Widget build(BuildContext context) {
    return _TeacherCard(
      icon: Icons.menu_book_outlined,
      title: klass?.name ?? 'Clase',
      subtitle: 'Sesiones registradas',
      onBack: onBack,
      actions: [
        _HeaderIconButton(
          icon: Icons.logout_rounded,
          onTap: onLogout,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading)
            SizedBox(
              height: 160,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
            )
          else if (sessions.isEmpty)
            Text(
              'Todavía no hay sesiones registradas para esta clase.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            )
          else ...[
            for (final session in sessions) ...[
              _HistorySessionTile(
                dateLabel: formatDate(session.startedAt),
                timeLabel: formatTime(session.startedAt),
                durationLabel: formatDuration(session),
                attendeesLabel:
                    '${session.attendeeCount} ${session.attendeeCount == 1 ? 'estudiante' : 'estudiantes'}',
                onTap: () => onSelect(session),
              ),
              const SizedBox(height: 12),
            ]
          ],
        ],
      ),
    );
  }
}

class _HistorySessionDetailView extends StatelessWidget {
  const _HistorySessionDetailView({
    required this.klass,
    required this.session,
    required this.attendees,
    required this.loading,
    required this.dateLabel,
    required this.startLabel,
    required this.durationLabel,
    required this.onBack,
    required this.onLogout,
  });

  final TeacherClass? klass;
  final ClassSessionSummary? session;
  final List<SessionAttendee> attendees;
  final bool loading;
  final String dateLabel;
  final String startLabel;
  final String durationLabel;
  final VoidCallback onBack;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return _TeacherCard(
      icon: Icons.event_available_rounded,
      title: 'Sesión del $dateLabel',
      subtitle: klass?.name ?? 'Clase',
      onBack: onBack,
      actions: [
        _HeaderIconButton(
          icon: Icons.logout_rounded,
          onTap: onLogout,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryInfoCard(
                  label: 'Hora inicio',
                  value: startLabel,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SummaryInfoCard(
                  label: 'Duración',
                  value: durationLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Asistentes (${attendees.length})',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          if (loading)
            SizedBox(
              height: 160,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
            )
          else if (attendees.isEmpty)
            Text(
              'No hubo registros de asistencia.',
              style:
                  Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: attendees.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, index) {
                final attendee = attendees[index];
                final when = attendee.at != null
                    ? DateTime.fromMillisecondsSinceEpoch(attendee.at! * 1000)
                        .toLocal()
                    : null;
                final timeLabel = when != null
                    ? '${when.hour.toString().padLeft(2, '0')}:'
                        '${when.minute.toString().padLeft(2, '0')}'
                    : '--:--';
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.white.withOpacity(0.12),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(
                      attendee.name?.isNotEmpty == true
                          ? attendee.name!
                          : attendee.code,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      "${attendee.email ?? ''} · $timeLabel",
                      style: TextStyle(color: Colors.white.withOpacity(0.7)),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ActiveSessionView extends StatelessWidget {
  const _ActiveSessionView({
    required this.klass,
    required this.startLabel,
    required this.elapsedLabel,
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
    required this.onFinish,
    required this.onLogout,
  });

  final TeacherClass? klass;
  final String startLabel;
  final String elapsedLabel;
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
  final VoidCallback onFinish;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return _TeacherCard(
      icon: Icons.qr_code_rounded,
      title: klass?.name ?? 'Sesión activa',
      subtitle: 'Sesión activa',
      actions: [
        _HeaderIconButton(
          icon: Icons.logout_rounded,
          onTap: onLogout,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryInfoCard(
                  label: 'Inicio',
                  value: startLabel.isEmpty ? '--:--' : startLabel,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SummaryInfoCard(
                  label: 'Expira',
                  value: expiryLabel,
                  highlight: expiryLabel == 'Expirada',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Text(
                  elapsedLabel,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tiempo transcurrido',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _dangerColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: onFinish,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Finalizar sesión'),
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
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
          ),
          const SizedBox(height: 28),
          Text(
            'Añadir por código o correo',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: addController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Código o correo...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: Color(0xFF4CC4FF)),
                    ),
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
                    borderRadius: BorderRadius.circular(16),
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
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: suggestions.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.white.withOpacity(0.1)),
                itemBuilder: (_, index) {
                  final suggestion = suggestions[index];
                  return ListTile(
                    leading: const Icon(Icons.person_outline,
                        color: Colors.white70),
                    title: Text(
                      suggestion['name']!.isNotEmpty
                          ? suggestion['name']!
                          : suggestion['email'] ?? suggestion['code'] ?? '',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      "${suggestion['email'] ?? ''} · ${suggestion['code'] ?? ''}",
                      style: TextStyle(color: Colors.white.withOpacity(0.7)),
                    ),
                    onTap: () => onSuggestionTap(suggestion),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 28),
          Text(
            'Asistentes: ${attendees.length}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          if (attendees.isEmpty)
            Text(
              'Aún no hay asistentes.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: attendees.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, index) {
                final attendee = attendees[index];
                final code = (attendee['code'] ?? '').toString();
                final name = (attendee['name'] ?? '').toString();
                final when = attendee['at'] is int
                    ? DateTime.fromMillisecondsSinceEpoch(
                            (attendee['at'] as int) * 1000)
                        .toLocal()
                    : null;
                final label = name.isNotEmpty ? name : code;
                final timeLabel = when != null
                    ? '${when.hour.toString().padLeft(2, '0')}:'
                        '${when.minute.toString().padLeft(2, '0')}'
                    : null;
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.white.withOpacity(0.12),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      "${attendee['email'] ?? ''}"
                      "${timeLabel != null ? ' · $timeLabel' : ''}",
                      style: TextStyle(color: Colors.white.withOpacity(0.7)),
                    ),
                    trailing: IconButton(
                      tooltip: 'Eliminar',
                      color: Colors.white70,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await confirmDelete(label);
                        if (ok && code.isNotEmpty) {
                          await onRemoveAttendee(code, label: label);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _TeacherCard extends StatelessWidget {
  const _TeacherCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.onBack,
    this.actions,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: _headerGradient,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 420;
                final hasActions = actions != null && actions!.isNotEmpty;
                final horizontalPadding = isCompact ? 20.0 : 24.0;
                final verticalPadding = isCompact ? 18.0 : 20.0;

                final spacedActions = <Widget>[];
                if (hasActions) {
                  for (var i = 0; i < actions!.length; i++) {
                    if (i > 0) {
                      spacedActions.add(SizedBox(width: isCompact ? 8 : 12));
                    }
                    spacedActions.add(actions![i]);
                  }
                }

                final iconSize = isCompact ? 48.0 : 52.0;

                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (onBack != null) ...[
                        _HeaderIconButton(
                          icon: Icons.arrow_back_rounded,
                          onTap: onBack!,
                        ),
                        SizedBox(width: isCompact ? 10 : 12),
                      ],
                      Container(
                        height: iconSize,
                        width: iconSize,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius:
                              BorderRadius.circular(isCompact ? 16 : 18),
                        ),
                        alignment: Alignment.center,
                        child: Icon(icon,
                            color: Colors.white, size: isCompact ? 24 : 26),
                      ),
                      SizedBox(width: isCompact ? 12 : 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            if (subtitle.isNotEmpty)
                              Padding(
                                padding:
                                    EdgeInsets.only(top: isCompact ? 2 : 4),
                                child: Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                        color: Colors.white.withOpacity(0.9),
                                      ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (hasActions) ...[
                        SizedBox(width: isCompact ? 10 : 16),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: spacedActions,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.18),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.logout_rounded, color: Colors.white), // Placeholder, overridden by icon param via IconTheme
        ),
      ),
    );
  }
}

class _ClassTile extends StatelessWidget {
  const _ClassTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _tileBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _tileBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child:
                    const Icon(Icons.menu_book_outlined, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistorySessionTile extends StatelessWidget {
  const _HistorySessionTile({
    required this.dateLabel,
    required this.timeLabel,
    required this.durationLabel,
    required this.attendeesLabel,
    required this.onTap,
  });

  final String dateLabel;
  final String timeLabel;
  final String durationLabel;
  final String attendeesLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _tileBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _tileBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child:
                    const Icon(Icons.event_note_rounded, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLabel,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Inicio: $timeLabel · $durationLabel',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      attendeesLabel,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white54),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryInfoCard extends StatelessWidget {
  const _SummaryInfoCard({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? _dangerColor : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}



