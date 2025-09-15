import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart' as mime;
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_theme.dart';
import 'verify_email_helper.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  // Nombres y apellidos (validados)
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController(); // opcional
  final _lastNameController = TextEditingController();
  final _secondLastNameController = TextEditingController(); // opcional
  final _codeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  // Programa académico (selección controlada)
  static const List<String> _programOptions = <String>[
    'Ingenieria de Sistemas',
    'Ingenieria Civil',
    'Ingenieria Financiera',
    'Administración Ambiental',
    'Administración Logística',
    'Administración Turística y Hotelera',
    'Contaduria Publica',
  ];
  String? _selectedProgram;
  final _roleController = TextEditingController(text: 'estudiante');
  final _expiryController = TextEditingController();

  DateTime? _expiryDate;
  Uint8List? _photoBytes;
  String? _photoMime; // image/jpeg | image/png | image/webp

  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _secondLastNameController.dispose();
    _codeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _roleController.dispose();
    _expiryController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        _expiryDate = picked;
        _expiryController.text =
            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  static const int _maxUploadBytes = 10 * 1024 * 1024; // 10 MB
  static const Set<String> _allowedMimes = {'image/jpeg', 'image/png', 'image/webp'};

  Future<void> _selectPhotoSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _pickPhoto(source);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxUploadBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La imagen supera 10MB. Elige otra o reduce su tamaño.')),
      );
      return;
    }
    final header = bytes.length >= 12 ? bytes.sublist(0, 12) : bytes;
    final detected = mime.lookupMimeType(file.path, headerBytes: header) ?? 'application/octet-stream';
    if (!_allowedMimes.contains(detected)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Formato no permitido. Usa JPG, PNG o WebP.')),
      );
      return;
    }
    setState(() {
      _photoBytes = bytes;
      _photoMime = detected;
    });
  }

  bool _isEducationalEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 0 || at == email.length - 1) return false;
    final domain = email.substring(at + 1).toLowerCase();
    if (domain.endsWith('.edu')) return true;
    final eduOrAcCcTld = RegExp(r"\.(edu|ac)\.[a-z]{2}$");
    if (eduOrAcCcTld.hasMatch(domain)) return true;
    const List<String> extraAllowed = [];
    for (final d in extraAllowed) {
      if (domain == d || domain.endsWith('.' + d)) return true;
    }
    return false;
  }

  String? _validateEducationalEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'El correo es obligatorio';
    final basic = RegExp(r'^.+@.+\..+$');
    if (!basic.hasMatch(v)) return 'Formato de correo inválido';
    if (!_isEducationalEmail(v)) {
      return 'Solo se permiten correos educativos (.edu, .edu.xx, .ac.xx)';
    }
    return null;
  }

  String? _validateCode(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'El código es obligatorio';
    if (!RegExp(r'^\d{4,}$').hasMatch(v)) return 'El código debe ser numérico (mín. 4 dígitos)';
    return null;
  }

  String? _validateFirstName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'El primer nombre es obligatorio';
    if (v.length < 2) return 'El primer nombre es muy corto';
    return null;
  }

  String? _validateLastName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'El primer apellido es obligatorio';
    if (v.length < 2) return 'El primer apellido es muy corto';
    return null;
  }

  String? _validatePassword(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'La contraseña es obligatoria';
    if (v.length < 8) return 'La contraseña debe tener al menos 8 caracteres';
    return null;
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form != null && !form.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Corrige los errores antes de continuar. Origen: validación local.')),
      );
      return;
    }
    final expiry = _expiryDate != null
        ? '${_expiryDate!.day.toString().padLeft(2, '0')}/${_expiryDate!.month.toString().padLeft(2, '0')}/${_expiryDate!.year}'
        : null;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    
    final firstName = _firstNameController.text.trim();
    final middleName = _middleNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final secondLastName = _secondLastNameController.text.trim();
    final fullName = [firstName, middleName, lastName, secondLastName].where((s) => s.isNotEmpty).join(' ');

    http
        .post(
      Uri.parse('${ApiConfig.baseUrl}/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': _codeController.text.trim(),
        'email': _emailController.text.trim(),
        'name': fullName,
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'secondLastName': secondLastName,
        'password': _passwordController.text,
        'program': _selectedProgram,
        'expiresAt': expiry,
        'role': 'student',
        'photo': _photoBytes != null && _photoMime != null
            ? 'data:${_photoMime!};base64,' + base64Encode(_photoBytes!)
            : null,
      }),
    )
        .then((resp) {
      Navigator.of(context).pop();
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final user = (data['user'] as Map?)?.cast<String, dynamic>();
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Registro exitoso'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_photoBytes != null)
                  Image.memory(_photoBytes!, width: 120, height: 120, fit: BoxFit.cover),
                if (user != null) ...[
                  const SizedBox(height: 8),
                  Text(user['name'] ?? ''),
                ],
                const SizedBox(height: 12),
                Text('Código efímero: ${data['ephemeralCode']}'),
              ],
            ),
          ),
        );
        Future.delayed(const Duration(seconds: 2), () {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        });
      } else {
        String msg = 'Error al registrar';
        try {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final err = (body['message'] ?? body['error'])?.toString();
          if (err != null && err.isNotEmpty) {
            msg = '$err (Origen: backend ${resp.statusCode})';
          } else {
            msg = 'Error (Origen: backend ${resp.statusCode})';
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }).catchError((e) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error de red (Origen: red): ${e.toString()}')));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registro'), actions: const [ThemeToggleButton()]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'Código (solo números)'),
                keyboardType: TextInputType.number,
                validator: _validateCode,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _firstNameController,
                decoration: const InputDecoration(labelText: 'Primer nombre'),
                validator: _validateFirstName,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _middleNameController,
                decoration: const InputDecoration(labelText: 'Segundo nombre (opcional)'),
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _lastNameController,
                decoration: const InputDecoration(labelText: 'Primer apellido'),
                validator: _validateLastName,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _secondLastNameController,
                decoration: const InputDecoration(labelText: 'Segundo apellido (opcional)'),
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo',
                  helperText: 'Usa tu correo institucional (.edu, .edu.xx, .ac.xx)',
                ),
                validator: _validateEducationalEmail,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Contraseña'),
                obscureText: true,
                validator: _validatePassword,
              ),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: _selectedProgram,
                decoration: const InputDecoration(labelText: 'Programa'),
                items: _programOptions
                    .map((p) => DropdownMenuItem<String>(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedProgram = v),
                validator: (v) => (_selectedProgram == null || _selectedProgram!.isEmpty)
                    ? 'Selecciona un programa'
                    : null,
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
                  child: TextFormField(
                    controller: _expiryController,
                    decoration: const InputDecoration(
                      labelText: 'Fecha de vencimiento (opcional)',
                      hintText: 'Típica renovación semestral automática',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Center(
                child: GestureDetector(
                  onTap: _selectPhotoSource,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade200,
                    ),
                    child: _photoBytes == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.photo_camera, size: 48),
                              SizedBox(height: 8),
                              Text('JPG/PNG/WebP · Máx 10MB', style: TextStyle(fontSize: 12)),
                            ],
                          )
                        : Image.memory(_photoBytes!, fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  final form = _formKey.currentState;
                  if (form != null && !form.validate()) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Corrige los errores antes de continuar.')),
                    );
                    return;
                  }
                  final ok = await verifyEmailWithOtp(context, _emailController.text.trim());
                  if (!ok) return;
                  _submit();
                },
                child: const Text('Registrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}