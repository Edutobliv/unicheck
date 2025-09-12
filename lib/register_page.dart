import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _programController = TextEditingController();
  DateTime? _expiryDate;
  Uint8List? _photoBytes;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }

  Future<void> _pickPhoto() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() => _photoBytes = bytes);
    }
  }

  Future<void> _submit() async {
    if (_nameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _programController.text.isEmpty ||
        _photoBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Completa todos los campos y la foto.')));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final user = {
      'id': id,
      'name': _nameController.text,
      'email': _emailController.text,
      'password': _passwordController.text,
      'program': _programController.text,
      'expiryDate': (_expiryDate ?? DateTime.now().add(const Duration(days: 365)))
          .toIso8601String(),
      'photo': base64Encode(_photoBytes!),
    };
    await prefs.setString('local_user', jsonEncode(user));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cuenta registrada. Inicia sesión.')));
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text('Registro'), actions: const [ThemeToggleButton()]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Correo'),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Contraseña'),
              obscureText: true,
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _programController,
              decoration: const InputDecoration(labelText: 'Programa'),
            ),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: _pickExpiryDate,
              child: AbsorbPointer(
                child: TextField(
                  decoration: InputDecoration(
                    labelText: 'Fecha de vencimiento',
                    hintText: _expiryDate == null
                        ? 'Opcional'
                        : '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.shade200,
                  ),
                  child: _photoBytes == null
                      ? const Icon(Icons.photo_camera, size: 60)
                      : Image.memory(_photoBytes!, fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submit,
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }
}

