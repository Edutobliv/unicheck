import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

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
  final String _baseUrl = "http://10.0.2.2:3000";

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
      final resp = await http.post(
        Uri.parse("$_baseUrl/auth/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": _emailController.text,
          "password": _passController.text,
        }),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token'] as String);
        final user = (data['user'] as Map).cast<String, dynamic>();
        await prefs.setString('role', user['role'] as String);
        await prefs.setString('code', user['code'] as String);
        await prefs.setString('name', user['name'] as String);
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
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
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
          ],
        ),
      ),
    );
  }
}
