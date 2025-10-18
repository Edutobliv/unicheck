import "dart:async";
import "dart:convert";
import "dart:typed_data";
import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter/foundation.dart" show kIsWeb;
import "package:http/http.dart" as http;
import "package:qr_flutter/qr_flutter.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:image_picker/image_picker.dart";
import "package:mime/mime.dart" as mime;
import "login_page.dart";
import "teacher_page.dart";
import "student_checkin_scanner.dart";
import "porter_page.dart";
import "app_theme.dart";
import "api_config.dart";
import "register_page.dart";
import "ui_kit.dart";
import "supabase_config.dart";
import "package:supabase_flutter/supabase_flutter.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Start UI immediately to avoid white screen if network init hangs on iOS
  runApp(const App());
  // Initialize Supabase in background with a short timeout
  unawaited(_initSupabase());
}

Future<void> _initSupabase() async {
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    ).timeout(const Duration(seconds: 4));
  } catch (_) {
    // Nonâ€‘blocking: app can operate with backend-only flows
  }
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppThemes.light(),
      routes: {
        '/carnet': (_) => const CarnetPage(),
        '/login': (_) => const LoginPage(),
        '/teacher': (_) => const TeacherPage(),
        '/porter': (_) => const PorterPage(),
        '/scan-checkin': (_) => const StudentCheckInScanner(),
        '/register': (_) => const RegisterPage(),
      },
      home: const LoginPage(),
    );
  }
}

class CarnetPage extends StatefulWidget {
  const CarnetPage({super.key});
  @override
  State<CarnetPage> createState() => _CarnetPageState();
}

class _CarnetPageState extends State<CarnetPage> {
  final String _baseUrl = ApiConfig.baseUrl; // backend por plataforma

  String? _qrUrl;
  int _secondsLeft = 0;
  Timer? _timer;
  Map<String, dynamic>? _student;
  String? _ephemeralCode;
  final ImagePicker _picker = ImagePicker();
  String?
  _photoEnsuredForCode; // evita solicitar la foto muchas veces por sesiÃƒÂ³n



  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _primeFromPrefs().whenComplete(_fetchQr);
    }
  }

  Future<void> _primeFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('code');
      final cachedPhotoData = code != null
          ? prefs.getString('photoData:$code')
          : null;
      final cachedPhotoUrl = code != null
          ? prefs.getString('photoUrl:$code')
          : null;
      setState(() {
        _student = {
          if (code != null) 'code': code,
          if (prefs.getString('name') != null) 'name': prefs.getString('name'),
          if (prefs.getString('program') != null)
            'program': prefs.getString('program'),
          if (prefs.getString('expiresAt') != null)
            'expiresAt': prefs.getString('expiresAt'),
          if (cachedPhotoData != null)
            'photoUrl': cachedPhotoData
          else if (cachedPhotoUrl != null)
            'photoUrl': cachedPhotoUrl,
        }..removeWhere((k, v) => v == null);
      });
    } catch (_) {}
  }

  Future<void> _fetchQr() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        if (mounted) Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
      final resp = await http.post(
        Uri.parse("$_baseUrl/issue-ephemeral"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _qrUrl = data["qrUrl"] as String;
          _secondsLeft = (data["ttl"] as num).toInt();
          _student = (data["student"] as Map?)?.cast<String, dynamic>();
          _ephemeralCode = data["ephemeralCode"] as String?;
        });
        // Completa valores faltantes desde cachÃƒÂ© (por ejemplo, nombre)
        try {
          if (_student != null) {
            final cachedName = prefs.getString('name');
            final currentName = _student!['name']?.toString().trim() ?? '';
            if (cachedName != null && currentName.isEmpty) {
              (_student!)['name'] = cachedName;
            }
          }
        } catch (_) {}
        await _ensurePhotoCacheForCurrentStudent();
        // Guardado/cachÃƒÂ© de foto firmada si viene en la respuesta
        final stu = _student;
        if (stu != null) {
          final signed = stu['photoUrl'] as String?;
          final expIn = (stu['photoUrlExpiresIn'] as num?)?.toInt() ?? 0;
          final code = (stu['code'] as String?) ?? prefs.getString('code');
          if (code != null &&
              signed != null &&
              signed.isNotEmpty &&
              expIn > 0) {
            final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            final expAt = now + expIn;
            await prefs.setString('photoUrl:$code', signed);
            await prefs.setInt('photoUrlExp:$code', expAt);
          } else {
            await _maybeRefreshSignedPhoto(prefs);
          }
        }
        _startCountdown();
        _maybeShowNoPhotoNotice();
      } else {
        if (resp.statusCode == 401) {
          if (await _tryRefreshToken()) {
            await _fetchQr();
            return;
          }
          _toast('SesiÃƒÂ³n expirada. Por favor ingresa nuevamente.');
          await _logout();
          return;
        }
        _toast('No se pudo generar el QR (${resp.statusCode}).');
      }
    } catch (e) {
      _toast('Error de red: $e');
    }
  }

  Future<void> _ensurePhotoCacheForCurrentStudent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stu = _student;
      final code = (stu?['code'] as String?) ?? prefs.getString('code');
      if (code == null) return;
      final existingData = prefs.getString('photoData:$code');
      if (existingData != null && existingData.isNotEmpty) {
        setState(() {
          (_student ??= <String, dynamic>{})['photoUrl'] = existingData;
        });
        _photoEnsuredForCode = code;
        return;
      }
      if (_photoEnsuredForCode == code) return; // ya intentado
      final signedFromStudent = stu?['photoUrl'] as String?;
      if (signedFromStudent != null && signedFromStudent.isNotEmpty) {
        await _cachePhotoFromSignedUrlOnce(signedFromStudent, prefs, code);
        _photoEnsuredForCode = code;
        return;
      }
      final token = prefs.getString('token');
      if (token == null) return;
      final resp = await http
          .get(
            Uri.parse("$_baseUrl/users/me/photo-url"),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final m = jsonDecode(resp.body) as Map<String, dynamic>;
        final signed = m['photoUrl'] as String?;
        if (signed != null && signed.isNotEmpty) {
          await _cachePhotoFromSignedUrlOnce(signed, prefs, code);
        }
      }
      _photoEnsuredForCode = code;
    } catch (_) {}
  }

  Future<void> _cachePhotoFromSignedUrlOnce(
    String signedUrl,
    SharedPreferences prefs,
    String code,
  ) async {
    try {
      final r = await http
          .get(Uri.parse(signedUrl))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final bytes = r.bodyBytes;
        final header = bytes.length >= 12 ? bytes.sublist(0, 12) : bytes;
        final detected =
            mime.lookupMimeType('', headerBytes: header) ?? 'image/jpeg';
        final dataUrl = 'data:$detected;base64,${base64Encode(bytes)}';
        await prefs.setString('photoData:$code', dataUrl);
        await prefs.remove('photoUrl:$code');
        await prefs.remove('photoUrlExp:$code');
        if (!mounted) return;
        setState(() {
          (_student ??= <String, dynamic>{})['photoUrl'] = dataUrl;
        });
      } else {
        await prefs.setString('photoUrl:$code', signedUrl);
      }
    } catch (_) {
      await prefs.setString('photoUrl:$code', signedUrl);
    }
  }

  Future<bool> _tryRefreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rt = prefs.getString('refreshToken');
      if (rt == null) return false;
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': rt}),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final m = jsonDecode(resp.body) as Map<String, dynamic>;
        await prefs.setString('token', m['token'] as String);
        if (m['refreshToken'] is String) {
          await prefs.setString('refreshToken', m['refreshToken'] as String);
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _maybeRefreshSignedPhoto(SharedPreferences? givenPrefs) async {
    try {
      final prefs = givenPrefs ?? await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;
      final code = prefs.getString('code');
      // Si ya tenemos data URL o ya lo intentamos para este code, salir
      if (code != null) {
        final cachedData = prefs.getString('photoData:$code');
        if (cachedData != null && cachedData.isNotEmpty) {
          setState(() {
            (_student ??= <String, dynamic>{})['photoUrl'] = cachedData;
          });
        }
        if (_photoEnsuredForCode == code) return;
      }
      final resp = await http
          .get(
            Uri.parse("$_baseUrl/users/me/photo-url"),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final m = jsonDecode(resp.body) as Map<String, dynamic>;
        final signed = m['photoUrl'] as String?;
        if (signed != null && signed.isNotEmpty && code != null) {
          await _cachePhotoFromSignedUrlOnce(signed, prefs, code);
        }
      }
    } catch (_) {}
  }

  void _maybeShowNoPhotoNotice() {
    final hasUrl = (_student?['photoUrl'] as String?)?.isNotEmpty == true;
    if (!hasUrl) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearMaterialBanners();
      messenger.showMaterialBanner(
        MaterialBanner(
          content: const Text(
            'Por favor sube una foto de perfil para tu carnet.',
          ),
          leading: const Icon(Icons.info_outline),
          actions: [
            TextButton(
              onPressed: () async {
                messenger.hideCurrentMaterialBanner();
                await _pickAndUploadPhoto();
              },
              child: const Text('Subir foto'),
            ),
            IconButton(
              tooltip: 'Cerrar',
              icon: const Icon(Icons.close),
              onPressed: () => messenger.hideCurrentMaterialBanner(),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    try {
      // Elegir fuente
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
                title: const Text("Elegir de galeria"),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;

      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      // ValidaciÃƒÂ³n ligera (el backend reoptimiza a <=3MB)
      if (bytes.length > 20 * 1024 * 1024) {
        _toast('La imagen es muy grande (>20MB).');
        return;
      }
      final header = bytes.length >= 12 ? bytes.sublist(0, 12) : bytes;
      final detected =
          mime.lookupMimeType(file.path, headerBytes: header) ??
          'application/octet-stream';
      if (!{'image/jpeg', 'image/png', 'image/webp'}.contains(detected)) {
        _toast('Formato no permitido. Usa JPG, PNG o WebP.');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final code = prefs.getString('code');
      if (token == null || code == null) {
        _toast("SesiÃƒÂ³n no vÃƒÂ¡lida. Ingresa nuevamente.");
        await _logout();
        return;
      }

      final dataUrl = 'data:$detected;base64,${base64Encode(bytes)}';
      final resp = await http
          .put(
            Uri.parse('$_baseUrl/users/me/photo'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'photo': dataUrl}),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        // cachea inmediatamente la imagen que el usuario subiÃƒÂ³
        await prefs.setString('photoData:$code', dataUrl);
        await prefs.remove('photoUrl:$code');
        await prefs.remove('photoUrlExp:$code');
        if (!mounted) return;
        setState(() {
          (_student ??= <String, dynamic>{})['photoUrl'] = dataUrl;
        });
        _toast('Foto actualizada.');
      } else if (resp.statusCode == 401) {
        _toast("SesiÃƒÂ³n expirada. Ingresa nuevamente.");
        await _logout();
      } else {
        _toast('No se pudo subir la foto (${resp.statusCode}).');
      }
    } catch (e) {
      _toast('Error al subir la foto: $e');
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _fetchQr();
      }
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('code');
    if (code != null) {
      await prefs.remove('photoUrl:$code');
      await prefs.remove('photoUrlExp:$code');
      await prefs.remove('photoData:$code');
    }
    // Limpieza preventiva de llaves globales antiguas
    await prefs.remove('photoUrl');
    await prefs.remove('photoUrlExp');
    await prefs.remove('token');
    await prefs.remove('role');
    await prefs.remove('name');
    await prefs.remove('code');
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }


  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      final theme = Theme.of(context);
      return BrandScaffold(
        title: 'Carnet digital',
        heroBackground: true,
        body: Center(
          child: FrostedPanel(
            width: 420,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.devices_other_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: BrandSpacing.sm),
                Text(
                  'Disponible solo en dispositivos moviles',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: BrandSpacing.xs),
                Text(
                  'Ingresa desde la aplicacion instalada en tu telefono autorizado para mostrar tu credencial dinamica.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final student = _student;

    return BrandScaffold(
      title: 'Carnet digital',
      heroBackground: true,
      actions: [
        IconButton(
          tooltip: 'Escanear asistencia',
          onPressed: () => Navigator.of(context).pushNamed('/scan-checkin'),
          icon: const Icon(Icons.qr_code_scanner),
        ),
        IconButton(
          tooltip: 'Cerrar sesion',
          onPressed: _logout,
          icon: const Icon(Icons.logout),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _fetchQr,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DigitalIdCard(
                student: student,
                qrUrl: _qrUrl,
                ephemeralCode: _ephemeralCode,
                secondsLeft: _secondsLeft,
                onUploadPhoto: _pickAndUploadPhoto,
              ),
              const SizedBox(height: BrandSpacing.lg),
              _QrStatusPanel(
                secondsLeft: _secondsLeft,
                onRefresh: _fetchQr,
              ),
              const SizedBox(height: BrandSpacing.lg),
              _AccountInfoPanel(
                student: student,
                onUploadPhoto: _pickAndUploadPhoto,
              ),
              const SizedBox(height: BrandSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}


// ---------- Widgets auxiliares ----------
class _DigitalIdCard extends StatelessWidget {
  final Map<String, dynamic>? student;
  final String? qrUrl;
  final String? ephemeralCode;
  final int secondsLeft;
  final VoidCallback onUploadPhoto;
  const _DigitalIdCard({
    required this.student,
    required this.qrUrl,
    required this.ephemeralCode,
    required this.secondsLeft,
    required this.onUploadPhoto,
  });
  @override
  Widget build(BuildContext context) {
    final name = (student?['name'] ?? 'Sin nombre').toString();
    final program = (student?['program'] ?? 'Programa pendiente').toString();
    final code = (student?['code'] ?? '--').toString();
    final expiry = (student?['expiresAt'] ?? 'Sin definir').toString();
    final role = (student?['role'] ?? 'ESTUDIANTE').toString().toUpperCase();
    final email = (student?['email'] ?? '').toString();

    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final isCompact = constraints.maxWidth < 520;
        final textAlign = isCompact ? TextAlign.center : TextAlign.start;
        final wrapAlignment = isCompact ? WrapAlignment.center : WrapAlignment.start;
        final photoWidth = isCompact ? 140.0 : 160.0;
        final photoHeight = isCompact ? 172.0 : 196.0;

        final photo = Stack(
          clipBehavior: Clip.none,
          children: [
            _FotoBox(
              photoAssetPath: 'assets/img/foto_carnet.png',
              photoUrl: student?['photoUrl'] as String?,
              width: photoWidth,
              height: photoHeight,
              onTap: onUploadPhoto,
            ),
            Positioned(
              bottom: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: BrandShadows.primaryButton(true),
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );

        final infoColumn = Column(
          crossAxisAlignment: isCompact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Align(
              alignment: isCompact ? Alignment.center : Alignment.centerLeft,
              child: const InfoBadge(
                icon: Icons.verified_user_outlined,
                label: 'Credencial activa',
              ),
            ),
            const SizedBox(height: BrandSpacing.sm),
            Text(
              name,
              style: theme.textTheme.headlineSmall,
              textAlign: textAlign,
            ),
            const SizedBox(height: BrandSpacing.xs),
            Text(
              program,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: textAlign,
            ),
            const SizedBox(height: BrandSpacing.sm),
            Wrap(
              alignment: wrapAlignment,
              runAlignment: wrapAlignment,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: BrandSpacing.sm,
              runSpacing: BrandSpacing.xs,
              children: [
                _InfoPill(
                  icon: Icons.badge_outlined,
                  label: 'Codigo $code',
                ),
                _InfoPill(
                  icon: Icons.event_outlined,
                  label: 'Vigencia $expiry',
                ),
                if (email.isNotEmpty)
                  _InfoPill(
                    icon: Icons.mail_outline,
                    label: email,
                  ),
                if (ephemeralCode != null && ephemeralCode!.isNotEmpty)
                  _InfoPill(
                    icon: Icons.lock_clock,
                    label: 'Token ${ephemeralCode!}',
                  ),
              ],
            ),
            const SizedBox(height: BrandSpacing.sm),
            Align(
              alignment: isCompact ? Alignment.center : Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: BrandGradients.primary(true),
                  borderRadius: BorderRadius.circular(BrandRadii.pill),
                  boxShadow: BrandShadows.primaryButton(true),
                ),
                child: Text(
                  role,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ],
        );

        final headerChildren = isCompact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  photo,
                  const SizedBox(height: BrandSpacing.md),
                  infoColumn,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  photo,
                  const SizedBox(width: BrandSpacing.lg),
                  Expanded(child: infoColumn),
                ],
              );

        return FrostedPanel(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 28),
          borderRadius: BrandRadii.large,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              headerChildren,
              const SizedBox(height: BrandSpacing.lg),
              Container(
                padding: const EdgeInsets.all(BrandSpacing.md),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [BrandColors.navySoft, BrandColors.navy],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(BrandRadii.large),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _QrGrande(qrUrl: qrUrl, size: 220),
                    const SizedBox(height: BrandSpacing.sm),
                    Text(
                      secondsLeft > 0
                          ? 'Renovacion automatica en ${secondsLeft.clamp(0, 999)} s'
                          : 'Generando nuevo codigo...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoPill({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(BrandRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
class _QrStatusPanel extends StatelessWidget {
  final int secondsLeft;
  final VoidCallback onRefresh;
  const _QrStatusPanel({required this.secondsLeft, required this.onRefresh});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool expiring = secondsLeft <= 10;
    final color = expiring ? theme.colorScheme.error : theme.colorScheme.primary;
    return FrostedPanel(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 30),
      borderRadius: BrandRadii.large,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Codigo dinamico', style: theme.textTheme.titleMedium),
          const SizedBox(height: BrandSpacing.xs),
          Text(
            'El QR se actualiza de forma frecuente para evitar copias o capturas.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: BrandSpacing.md),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.timer_outlined, color: color),
              ),
              const SizedBox(width: BrandSpacing.sm),
              Text(
                secondsLeft > 0
                    ? 'Renovacion en ${secondsLeft.clamp(0, 999)} s'
                    : 'Actualizando...',
                style: theme.textTheme.titleMedium?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: BrandSpacing.md),
          PrimaryButton(
            onPressed: onRefresh,
            expand: false,
            child: const Text('Generar nuevo QR'),
          ),
        ],
      ),
    );
  }
}
class _AccountInfoPanel extends StatelessWidget {
  final Map<String, dynamic>? student;
  final VoidCallback onUploadPhoto;
  const _AccountInfoPanel({
    required this.student,
    required this.onUploadPhoto,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = (student?['code'] ?? '--').toString();
    final program = (student?['program'] ?? 'Programa pendiente').toString();
    final expiry = (student?['expiresAt'] ?? 'Sin definir').toString();
    final email = (student?['email'] ?? '').toString();
    return FrostedPanel(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
      borderRadius: BrandRadii.large,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Detalles de la cuenta', style: theme.textTheme.titleMedium),
          const SizedBox(height: BrandSpacing.sm),
          _DetailRow(
            label: 'Codigo',
            value: code,
            icon: Icons.badge_outlined,
          ),
          _DetailRow(
            label: 'Programa',
            value: program,
            icon: Icons.school_outlined,
          ),
          _DetailRow(
            label: 'Vigencia',
            value: expiry,
            icon: Icons.event_outlined,
          ),
          if (email.isNotEmpty)
            _DetailRow(
              label: 'Correo',
              value: email,
              icon: Icons.alternate_email,
            ),
          //const SizedBox(height: BrandSpacing.md),
          //SecondaryButton(
          //  onPressed: onUploadPhoto,
          //  child: const Text('Actualizar foto'),
          //),
        ],
      ),
    );
  }
}
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  const _DetailRow({required this.label, required this.value, this.icon});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: BrandSpacing.xs),
          ],
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
class _FotoBox extends StatefulWidget {
  final String? photoUrl;
  final String photoAssetPath;
  final double width;
  final double height;
  final VoidCallback? onTap;
  const _FotoBox({
    required this.photoAssetPath,
    this.photoUrl,
    this.width = 150,
    this.height = 175,
    this.onTap,
  });
  @override
  State<_FotoBox> createState() => _FotoBoxState();
}
class _FotoBoxState extends State<_FotoBox> {
  ImageProvider? _provider;
  Uint8List? _bytes;
  @override
  void initState() {
    super.initState();
    _computeProvider();
  }
  @override
  void didUpdateWidget(covariant _FotoBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl ||
        oldWidget.photoAssetPath != widget.photoAssetPath) {
      _computeProvider();
    }
  }
  void _computeProvider() {
    final url = widget.photoUrl;
    try {
      if (url != null && url.isNotEmpty) {
        if (url.startsWith('data:image')) {
          final b64 = url.split(',').last;
          _bytes = base64Decode(b64);
          _provider = MemoryImage(_bytes!);
        } else if (url.startsWith('http://') || url.startsWith('https://')) {
          _provider = CachedNetworkImageProvider(url);
        } else {
          _provider = AssetImage(widget.photoAssetPath);
        }
      } else {
        _provider = AssetImage(widget.photoAssetPath);
      }
    } catch (_) {
      _provider = AssetImage(widget.photoAssetPath);
    }
  }
  @override
  Widget build(BuildContext context) {
    final image = _provider != null
        ? Image(
            image: _provider!,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          )
        : Image.asset(widget.photoAssetPath, fit: BoxFit.cover);
    final outerRadius = BorderRadius.circular(22);
    final innerRadius = BorderRadius.circular(18);
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          gradient: BrandGradients.surface,
          borderRadius: outerRadius,
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
            width: 1.4,
          ),
          boxShadow: BrandShadows.surface,
        ),
        child: ClipRRect(borderRadius: innerRadius, child: image),
      ),
    );
  }
}
class _QrGrande extends StatelessWidget {
  final String? qrUrl;
  final double size;
  const _QrGrande({this.qrUrl, this.size = 220});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: BrandGradients.surface,
        borderRadius: BorderRadius.circular(BrandRadii.large),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.18)),
        boxShadow: BrandShadows.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(BrandRadii.medium),
          ),
          child: Center(
            child: qrUrl == null
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.95, end: 1).animate(
                          CurvedAnimation(
                            parent: anim,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                        child: child,
                      ),
                    ),
                    child: QrImageView(
                      key: ValueKey(qrUrl),
                      data: qrUrl!,
                      version: QrVersions.auto,
                      backgroundColor: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}























