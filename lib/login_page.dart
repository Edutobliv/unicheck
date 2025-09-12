import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'api_config.dart';
import 'user_storage.dart';

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
    if (role == 'student' && token != null && prefs.getString('email') != null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/carnet');
    }
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    final password = _passController.text;

    try {
      final resp = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/auth/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final userApi = (data['user'] as Map).cast<String, dynamic>();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token'] as String);
        await prefs.setString('role', userApi['role'] as String);
        await prefs.setString('name', userApi['name'] as String);
        await prefs.setString('email', userApi['email'] as String);
        await prefs.setString('id', userApi['code'] as String);
        await prefs.setString('code', userApi['code'] as String);

        final local = await UserStorage.findUser(email);
        if (local != null) {
          await prefs.setString('program', local['program'] as String);
          await prefs.setString('photo', local['photo'] as String);
          if (local['expiryDate'] != null) {
            await prefs.setString('expiryDate', local['expiryDate'] as String);
          } else {
            await prefs.remove('expiryDate');
          }
        } else {
          await prefs.remove('program');
          await prefs.remove('photo');
          await prefs.remove('expiryDate');
        }

        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/carnet');
        return;
      } else if (resp.statusCode == 401) {
        setState(() {
          _error = 'Credenciales inválidas';
        });
      } else {
        setState(() {
          _error = 'Error del servidor (${resp.statusCode})';
        });
      }
    } catch (_) {
      final user = await UserStorage.findUser(email);
      if (user != null && user['password'] == password) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('role', 'student');
        await prefs.setString('name', user['name'] as String);
        await prefs.setString('email', user['email'] as String);
        await prefs.setString('program', user['program'] as String);
        await prefs.setString('id', user['id'] as String);
        await prefs.setString('code', user['id'] as String);
        if (user['expiryDate'] != null) {
          await prefs.setString('expiryDate', user['expiryDate'] as String);
        } else {
          await prefs.remove('expiryDate');
        }
        await prefs.setString('photo', user['photo'] as String);
        await prefs.remove('token');
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/carnet');
        return;
      } else {
        setState(() {
          _error = 'Credenciales inválidas';
        });
      }
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
