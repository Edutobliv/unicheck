import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart' as mime;
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'ui_kit.dart';
import 'verify_email_helper.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _secondLastNameController = TextEditingController();
  final _codeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _roleController = TextEditingController(text: 'estudiante');
  final _expiryController = TextEditingController();

  static const List<String> _programOptions = <String>[
    'Ingenieria de Sistemas',
    'Ingenieria Civil',
    'Ingenieria Financiera',
    'Administracion Ambiental',
    'Administracion Logistica',
    'Administracion Turistica y Hotelera',
    'Contaduria Publica',
  ];

  String? _selectedProgram;
  DateTime? _expiryDate;
  Uint8List? _photoBytes;
  String? _photoMime;

  final ImagePicker _picker = ImagePicker();
  bool _submitting = false;

  static const int _maxUploadBytes = 10 * 1024 * 1024; // 10 MB
  static const Set<String> _allowedMimes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

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
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _expiryDate = picked;
        _expiryController.text =
            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

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
              title: const Text('Elegir de galeria'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
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
    if (!mounted) return;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > _maxUploadBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La imagen supera 10MB. Elige otra o reduce su tamano.'),
        ),
      );
      return;
    }
    final detected = mime.lookupMimeType(file.path, headerBytes: bytes.take(12).toList());
    if (detected == null || !_allowedMimes.contains(detected)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Formato no soportado. Usa JPG, PNG o WebP.'),
        ),
      );
      return;
    }
    setState(() {
      _photoBytes = bytes;
      _photoMime = detected;
    });
  }

  String? _validateEducationalEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'El correo es obligatorio';
    final basic = RegExp(r'^.+@.+\..+$');
    if (!basic.hasMatch(v)) return 'Formato de correo invalido';
    if (!_isEducationalEmail(v)) {
      return 'Solo se permiten correos educativos (.edu o .ac)';
    }
    return null;
  }

  String? _validateCode(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'El codigo es obligatorio';
    if (!RegExp(r'^\d{4,}$').hasMatch(v)) {
      return 'El codigo debe ser numerico (min. 4 digitos)';
    }
    return null;
  }

  String? _validateFirstName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'El primer nombre es obligatorio';
    if (v.length < 2) return 'Ingresa un nombre valido';
    return null;
  }

  String? _validateLastName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'El primer apellido es obligatorio';
    if (v.length < 2) return 'Ingresa un apellido valido';
    return null;
  }

  String? _validatePassword(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'La contraseña es obligatoria';
    if (v.length < 8) return 'La contraseña debe tener al menos 8 caracteres';
    return null;
  }

  bool _isEducationalEmail(String email) {
    final lowered = email.toLowerCase();
    return lowered.endsWith('.edu') || lowered.contains('.edu.') || lowered.contains('.ac.');
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form != null && !form.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Corrige los errores antes de continuar.'),
        ),
      );
      return;
    }

    final ok = await verifyEmailWithOtp(
      context,
      _emailController.text.trim(),
    );
    if (!mounted || !ok) return;

    setState(() => _submitting = true);

    final expiry = _expiryDate != null
        ? '${_expiryDate!.day.toString().padLeft(2, '0')}/${_expiryDate!.month.toString().padLeft(2, '0')}/${_expiryDate!.year}'
        : null;
    final firstName = _firstNameController.text.trim();
    final middleName = _middleNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final secondLastName = _secondLastNameController.text.trim();
    final fullName = [firstName, middleName, lastName, secondLastName]
        .where((s) => s.isNotEmpty)
        .join(' ');

    try {
      final resp = await http.post(
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
              ? 'data:${_photoMime!};base64,${base64Encode(_photoBytes!)}'
              : null,
        }),
      );

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final user = (data['user'] as Map?)?.cast<String, dynamic>();
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Registro exitoso'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_photoBytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      _photoBytes!,
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: BrandSpacing.sm),
                ],
                if (user != null) ...[
                  Text(
                    user['name'] ?? '',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: BrandSpacing.xs),
                ],
                Text('Codigo efimero: ${data['ephemeralCode']}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Continuar'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      } else {
        String msg = 'No pudimos completar el registro. Intenta nuevamente.';
        try {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final err = (body['message'] ?? body['error'])?.toString();
          if (err != null && err.isNotEmpty) {
            msg = err;
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo conectar con el servidor. Verifica tu conexion e intenta nuevamente.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      title: 'Crear cuenta',
      heroBackground: true,
      padding: EdgeInsets.zero,
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pushReplacementNamed('/login'),
          child: const Text('Iniciar sesion'),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1000;
          final horizontalPadding = isWide ? 72.0 : 24.0;
          final verticalPadding = isWide ? 48.0 : 24.0;
          final hero = _RegisterHero(
            compact: !isWide,
            onLogin: _submitting
                ? null
                : () => Navigator.of(context).pushReplacementNamed('/login'),
          );
          final form = _RegisterFormCard(
            formKey: _formKey,
            codeController: _codeController,
            firstNameController: _firstNameController,
            middleNameController: _middleNameController,
            lastNameController: _lastNameController,
            secondLastNameController: _secondLastNameController,
            emailController: _emailController,
            passwordController: _passwordController,
            roleController: _roleController,
            expiryController: _expiryController,
            selectedProgram: _selectedProgram,
            programOptions: _programOptions,
            onProgramChanged: (value) => setState(() => _selectedProgram = value),
            onPickExpiry: _pickExpiryDate,
            photoBytes: _photoBytes,
            onPickPhoto: _selectPhotoSource,
            onSubmit: _submit,
            submitting: _submitting,
            validators: _FormValidators(
              code: _validateCode,
              firstName: _validateFirstName,
              lastName: _validateLastName,
              educationalEmail: _validateEducationalEmail,
              password: _validatePassword,
            ),
          );

          if (isWide) {
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: hero),
                  const SizedBox(width: BrandSpacing.xl),
                  Expanded(child: form),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              verticalPadding,
              horizontalPadding,
              BrandSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                hero,
                const SizedBox(height: BrandSpacing.xl),
                form,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FormValidators {
  const _FormValidators({
    required this.code,
    required this.firstName,
    required this.lastName,
    required this.educationalEmail,
    required this.password,
  });

  final String? Function(String?) code;
  final String? Function(String?) firstName;
  final String? Function(String?) lastName;
  final String? Function(String?) educationalEmail;
  final String? Function(String?) password;
}

class _RegisterHero extends StatelessWidget {
  const _RegisterHero({required this.compact, required this.onLogin});

  final bool compact;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textAlign = compact ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const InfoBadge(
          icon: Icons.auto_awesome,
          label: 'Credencial digital en minutos',
        ),
        const SizedBox(height: BrandSpacing.lg),
        Text(
          'Registra tu acceso inteligente',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            letterSpacing: -0.6,
            height: 1.05,
          ),
          textAlign: textAlign,
        ),
        const SizedBox(height: BrandSpacing.sm),
        Text(
          'Comparte accesos seguros con tokens efimeros, gestiona fotos y vence en automatico sin planillas.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.86),
          ),
          textAlign: textAlign,
        ),
        const SizedBox(height: BrandSpacing.lg),
        Wrap(
          alignment: compact ? WrapAlignment.center : WrapAlignment.start,
          spacing: BrandSpacing.sm,
          runSpacing: BrandSpacing.sm,
          children: const [
            _HeroChip(icon: Icons.qr_code_2, label: 'QR seguro'),
            _HeroChip(icon: Icons.people_alt_outlined, label: 'Registro de Estudiantes'),
          ],
        ),
      ],
    );
  }
}

class _RegisterFormCard extends StatelessWidget {
  const _RegisterFormCard({
    required this.formKey,
    required this.codeController,
    required this.firstNameController,
    required this.middleNameController,
    required this.lastNameController,
    required this.secondLastNameController,
    required this.emailController,
    required this.passwordController,
    required this.roleController,
    required this.expiryController,
    required this.selectedProgram,
    required this.programOptions,
    required this.onProgramChanged,
    required this.onPickExpiry,
    required this.photoBytes,
    required this.onPickPhoto,
    required this.onSubmit,
    required this.submitting,
    required this.validators,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController codeController;
  final TextEditingController firstNameController;
  final TextEditingController middleNameController;
  final TextEditingController lastNameController;
  final TextEditingController secondLastNameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController roleController;
  final TextEditingController expiryController;
  final String? selectedProgram;
  final List<String> programOptions;
  final ValueChanged<String?> onProgramChanged;
  final VoidCallback onPickExpiry;
  final Uint8List? photoBytes;
  final VoidCallback onPickPhoto;
  final VoidCallback onSubmit;
  final bool submitting;
  final _FormValidators validators;

  @override
  Widget build(BuildContext context) {
    return FrostedPanel(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 28),
      borderRadius: BrandRadii.large,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth > 520;
          final fieldWidth = twoColumns
              ? (constraints.maxWidth - BrandSpacing.sm) / 2
              : constraints.maxWidth;

          Widget wrapField(Widget field) => SizedBox(
                width: fieldWidth,
                child: field,
              );

          return Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  title: 'Datos personales',
                  caption: 'Usaremos esta informacion para generar tu credencial digital.',
                ),
                const SizedBox(height: BrandSpacing.md),
                Wrap(
                  spacing: BrandSpacing.sm,
                  runSpacing: BrandSpacing.sm,
                  children: [
                    wrapField(
                      TextFormField(
                        controller: codeController,
                        decoration: const InputDecoration(
                          labelText: 'Codigo (solo numeros)',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        keyboardType: TextInputType.number,
                        validator: validators.code,
                      ),
                    ),
                    wrapField(
                      TextFormField(
                        controller: firstNameController,
                        decoration: const InputDecoration(
                          labelText: 'Primer nombre',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: validators.firstName,
                      ),
                    ),
                    wrapField(
                      TextFormField(
                        controller: middleNameController,
                        decoration: const InputDecoration(
                          labelText: 'Segundo nombre (opcional)',
                          prefixIcon: Icon(Icons.person_add_alt_1_outlined),
                        ),
                      ),
                    ),
                    wrapField(
                      TextFormField(
                        controller: lastNameController,
                        decoration: const InputDecoration(
                          labelText: 'Primer apellido',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: validators.lastName,
                      ),
                    ),
                    wrapField(
                      TextFormField(
                        controller: secondLastNameController,
                        decoration: const InputDecoration(
                          labelText: 'Segundo apellido (opcional)',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BrandSpacing.lg),
                const SectionHeader(
                  title: 'Contacto y acceso',
                  caption: 'Confirma tu correo institucional que sera verificado por Codigo y una contraseña segura para la cuenta.',
                ),
                const SizedBox(height: BrandSpacing.md),
                Wrap(
                  spacing: BrandSpacing.sm,
                  runSpacing: BrandSpacing.sm,
                  children: [
                    wrapField(
                      TextFormField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'Correo institucional',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: validators.educationalEmail,
                      ),
                    ),
                    wrapField(
                      TextFormField(
                        controller: passwordController,
                        decoration: const InputDecoration(
                          labelText: 'contraseña',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                        validator: validators.password,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BrandSpacing.lg),
                const SectionHeader(
                  title: 'Programa academico',
                  caption: 'Define el programa academico.',
                ),
                const SizedBox(height: BrandSpacing.md),
                Wrap(
                  spacing: BrandSpacing.sm,
                  runSpacing: BrandSpacing.sm,
                  children: [
                    wrapField(
                      DropdownButtonFormField<String>(
                      initialValue: selectedProgram,
                        decoration: const InputDecoration(
                          labelText: 'Programa academico',
                          prefixIcon: Icon(Icons.school_outlined),
                        ),
                        isExpanded: true,
                        items: programOptions
                            .map(
                              (option) => DropdownMenuItem<String>(
                                value: option,
                                child: Text(option),
                              ),
                            )
                            .toList(),
                        onChanged: onProgramChanged,
                      ),
                    ),
                    wrapField(
                      TextFormField(
                        controller: roleController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Rol asignado',
                          prefixIcon: Icon(Icons.verified_user_outlined),
                        ),
                      ),
                    ),
                    // Fecha de vencimiento deshabilitada temporalmente
                    //wrapField(
                    //  GestureDetector(
                    //    onTap: onPickExpiry,
                    //    child: AbsorbPointer(
                    //      child: TextFormField(
                    //        controller: expiryController,
                    //        decoration: const InputDecoration(
                    //          labelText: 'Fecha de vencimiento (opcional)',
                    //          prefixIcon: Icon(Icons.event_outlined),
                    //        ),
                    //      ),
                    //    ),
                    //  ),
                    //),
                  ],
                ),
                const SizedBox(height: BrandSpacing.lg),
                const SectionHeader(
                  title: 'Foto de perfil (opcional)',
                  caption: 'Puedes cargar una foto ahora o actualizarla luego desde la app.',
                ),
                const SizedBox(height: BrandSpacing.md),
                _PhotoPickerTile(
                  photoBytes: photoBytes,
                  onPickPhoto: onPickPhoto,
                ),
                const SizedBox(height: BrandSpacing.lg),
                PrimaryButton(
                  onPressed: submitting ? null : onSubmit,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: submitting
                        ? const SizedBox(
                            key: ValueKey('loading'),
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Text('Registrar cuenta'),
                  ),
                ),
                const SizedBox(height: BrandSpacing.sm),
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(context).pushReplacementNamed('/login'),
                  child: const Text('Volver al inicio de sesion'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PhotoPickerTile extends StatelessWidget {
  const _PhotoPickerTile({required this.photoBytes, required this.onPickPhoto});

  final Uint8List? photoBytes;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onPickPhoto,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: BrandGradients.surface,
          borderRadius: BorderRadius.circular(BrandRadii.large),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.4),
          ),
        ),
        child: photoBytes == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.photo_camera_back_outlined,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: BrandSpacing.sm),
                  Text(
                    'Subir foto (JPG/PNG/WebP)',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: BrandSpacing.xs),
                  Text(
                    'Tamano maximo 10MB. Recomendado fondo neutro.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(BrandRadii.medium),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Image.memory(
                    photoBytes!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(BrandRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: BrandSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}





