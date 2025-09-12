import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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

  @override
  void initState() {
    super.initState();
    _checkToken();
  }

  Future<void> _checkToken() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');
    final token = prefs.getString('token');
    if (role == 'student' && token != null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/carnet');
    }
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/auth/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'email': _emailController.text.trim(),
          'password': _passController.text,
        }),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final user = (data['user'] as Map).cast<String, dynamic>();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token'] as String);
        await prefs.setString('role', user['role'] as String);
        await prefs.setString('name', user['name'] as String);
        await prefs.setString('email', user['email'] as String);
        await prefs.setString('id', user['code'] as String);
        if (user['program'] != null) {
          await prefs.setString('program', user['program'] as String);
        } else {
          await prefs.remove('program');
        }
        if (user['expiryDate'] != null) {
          await prefs.setString('expiryDate', user['expiryDate'] as String);
        } else {
          await prefs.remove('expiryDate');
        }
        if (user['photo'] != null) {
          await prefs.setString('photo', user['photo'] as String);
        } else {
          await prefs.remove('photo');
        }
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/carnet');
      } else {
        setState(() {
          _error = 'Credenciales inválidas';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error de conexión';
      });
    }
    if (mounted) {
      setState(() {
        _loading = false;
      });
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
              decoration: const InputDecoration(labelText: 'Email'),
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
