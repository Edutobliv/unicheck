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
      final Map<String, String> payload = _emailController.text.contains('@')
          ? {
              "email": _emailController.text,
              "password": _passController.text,
            }
          : {
              "code": _emailController.text,
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
        await prefs.setString('role', user['role'] as String);
        await prefs.setString('code', user['code'] as String);
        await prefs.setString('name', user['name'] as String);
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
        setState(() {
          _error = 'Credenciales inválidas';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error de red';
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
