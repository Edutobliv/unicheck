import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import 'app_theme.dart';
import 'api_config.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _programController = TextEditingController();
  final _roleController = TextEditingController(text: 'student');
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

  void _submit() {
    final expiry = _expiryDate != null
        ? '${_expiryDate!.day.toString().padLeft(2, '0')}/${_expiryDate!.month.toString().padLeft(2, '0')}/${_expiryDate!.year}'
        : null;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    http
        .post(
      Uri.parse('${ApiConfig.baseUrl}/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': _codeController.text,
        'email': _emailController.text,
        'name': _nameController.text,
        'password': _passwordController.text,
        'program': _programController.text,
        'expiresAt': expiry,
        'role': _roleController.text,
        'photo': _photoBytes != null ? 'data:image/png;base64,' + base64Encode(_photoBytes!) : null,
      }),
    )
        .then((resp) {
      Navigator.of(context).pop();
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Registro exitoso'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_photoBytes != null)
                  Image.memory(_photoBytes!, width: 120, height: 120, fit: BoxFit.cover),
                const SizedBox(height: 12),
                Text('Código efímero: ${data['ephemeralCode']}'),
              ],
            ),
          ),
        );
        Future.delayed(const Duration(seconds: 2), () {
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/login', (route) => false);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al registrar')),
        );
      }
    }).catchError((_) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Error de red')));
    });
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
              controller: _codeController,
              decoration: const InputDecoration(labelText: 'Código'),
            ),
            const SizedBox(height: 15),
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
            TextField(
              controller: _roleController,
              decoration: const InputDecoration(labelText: 'Rol'),
              readOnly: true,
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

