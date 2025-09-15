import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'api_config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  bool _loading = false;
  String? _error;
  // Base URL now resolves per-platform (web/desktop: localhost, Android emulator: 10.0.2.2)
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
      // En web permitimos acceso solo a profesores
      if (kIsWeb && role != 'teacher') {
        await prefs.remove('token');
        await prefs.remove('role');
        await prefs.remove('name');
        await prefs.remove('code');
        if (mounted) {
          setState(() {
            _error = 'Acceso web solo para profesores. Por favor ingresa desde tu celular vinculado.';
          });
        }
        return;
      }
      if (!mounted) return;
      String route;
      if (role == 'teacher') {
        route = '/teacher';
      } else if (role == 'porter') route = '/porter';
      else route = '/carnet';
      Navigator.of(context).pushReplacementNamed(route);
    }
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final input = _emailController.text.trim();
      final isEmail = input.contains('@');
      // Validación local: si es código (no email), debe ser numérico
      if (!isEmail) {
        final codeOk = RegExp(r'^\d{4,}$').hasMatch(input);
        if (!codeOk) {
          setState(() {
            _error = 'El código debe ser numérico (mín. 4 dígitos). Origen: validación local.';
          });
          return;
        }
      }

      final Map<String, String> payload = isEmail
          ? {
              "email": input,
              "password": _passController.text,
            }
          : {
              "code": input,
              "password": _passController.text,
            };

      final resp = await http
          .post(
        Uri.parse("$_baseUrl/auth/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token'] as String);
        final user = (data['user'] as Map).cast<String, dynamic>();
        final code = user['code'] as String;
        await prefs.setString('role', user['role'] as String);
        await prefs.setString('code', code);
        await prefs.setString('name', user['name'] as String);
        if (user['expiresAt'] is String) {
          await prefs.setString('expiresAt', user['expiresAt'] as String);
        }
        if (user['program'] is String) {
          await prefs.setString('program', user['program'] as String);
        }
        // Limpiar caché global previa y cachear por usuario
        await prefs.remove('photoUrl');
        await prefs.remove('photoUrlExp');
        if (user['photoUrl'] is String) {
          await prefs.setString('photoUrl:'+code, user['photoUrl'] as String);
          // TTL aproximado (login firma por ~300s); si se requiere precisión, se puede exponer desde el backend
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          await prefs.setInt('photoUrlExp:'+code, now + 300);
        } else {
          await prefs.remove('photoUrl:'+code);
          await prefs.remove('photoUrlExp:'+code);
        }
        // En web, solo profesores pueden continuar
        final role = user['role'] as String?;
        if (kIsWeb && role != 'teacher') {
          await prefs.remove('token');
          await prefs.remove('role');
          await prefs.remove('name');
          await prefs.remove('code');
          if (mounted) {
            setState(() {
              _error = role == 'porter'
                  ? 'El panel de portería no está disponible en la web. Usa el celular vinculado a tu cuenta.'
                  : 'El acceso de estudiante no está disponible en la web. Ingresa desde tu celular vinculado.';
            });
          }
          return;
        }
        if (!mounted) return;
        String route;
        if (user['role'] == 'teacher') {
          route = '/teacher';
        } else if (user['role'] == 'porter') route = '/porter';
        else route = '/carnet';
        Navigator.of(context).pushReplacementNamed(route);
      } else {
        String msg = 'Credenciales inválidas';
        try {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final err = (body['message'] ?? body['error'])?.toString();
          if (err != null && err.isNotEmpty) {
            msg = err + ' (Origen: backend ' + resp.statusCode.toString() + ')';
          } else {
            msg = 'Error (Origen: backend ' + resp.statusCode.toString() + ')';
          }
        } catch (_) {}
        setState(() { _error = msg; });
      }
    } catch (e) {
      setState(() {
        _error = 'Error de red: ${e.toString()} (Origen: red)';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login'), actions: const [ThemeToggleButton()]),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Correo o código'),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _login,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Ingresar'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pushNamed('/register'),
              child: const Text('Crear cuenta'),
            ),
          ],
        ),
      ),
    );
  }
}
