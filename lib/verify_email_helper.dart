import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';

// Ajustes de control de abuso
const int _kResendCooldownSec = 60; // segundos entre reenvíos
const int _kMaxResends = 3; // máximo reenvíos permitidos
const int _kMaxVerifyAttempts = 3; // máximo intentos de verificación

Future<bool> verifyEmailWithOtp(BuildContext context, String email) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!SupabaseConfig.isConfigured) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Configura SUPABASE_URL y SUPABASE_ANON_KEY para verificar el correo.',
        ),
      ),
    );
    return false;
  }
  // Envio inicial del OTP
  try {
    await Supabase.instance.client.auth.signInWithOtp(email: email);
  } catch (e) {
    if (!context.mounted) return false;
    messenger.showSnackBar(
      SnackBar(content: Text('No se pudo enviar el codigo: $e')),
    );
    return false;
  }
  if (!context.mounted) return false;

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OtpDialog(email: email),
  );
  try {
    await Supabase.instance.client.auth.signOut();
  } catch (_) {}
  return ok == true;
}

class _OtpDialog extends StatefulWidget {
  final String email;
  const _OtpDialog({required this.email});
  @override
  State<_OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<_OtpDialog> {
  final TextEditingController _codeCtrl = TextEditingController();
  String? _errorText;
  bool _verifying = false;
  int _resends = 0;
  int _attempts = 0;
  int _cooldownLeft =
      _kResendCooldownSec; // empieza cooldown tras el primer envío
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    // Ticker simple basado en Timer.periodic
    _ticker = Ticker(
      onTick: () {
        if (!mounted) return;
        setState(() {
          if (_cooldownLeft > 0) _cooldownLeft--;
        });
      },
    );
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _resend() async {
    if (_resends >= _kMaxResends) {
      setState(
        () => _errorText =
            'Has alcanzado el máximo de reenvíos. Inténtalo más tarde.',
      );
      return;
    }
    if (_cooldownLeft > 0) return;
    try {
      await Supabase.instance.client.auth.signInWithOtp(email: widget.email);
      if (!mounted) return;
      setState(() {
        _resends++;
        _cooldownLeft = _kResendCooldownSec;
        _errorText = null;
      });
    } catch (e) {
      setState(() => _errorText = 'No se pudo reenviar: $e');
    }
  }

  Future<void> _verify() async {
    final v = _codeCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(v)) {
      setState(() => _errorText = 'Debe tener 6 dígitos');
      return;
    }
    if (_attempts >= _kMaxVerifyAttempts) {
      setState(
        () => _errorText = 'Se agotaron los intentos. Inténtalo más tarde.',
      );
      return;
    }
    setState(() {
      _verifying = true;
      _errorText = null;
    });
    try {
      await Supabase.instance.client.auth.verifyOTP(
        email: widget.email,
        token: v,
        type: OtpType.email,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _attempts++;
        _verifying = false;
        _errorText =
            'Código inválido o vencido. Intento $_attempts/$_kMaxVerifyAttempts';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _cooldownLeft == 0 && _resends < _kMaxResends;
    final verifyDisabled = _verifying || _attempts >= _kMaxVerifyAttempts;
    return AlertDialog(
      title: const Text('Verifica tu correo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Ingresa el código de 6 dígitos enviado a tu correo.'),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: 'Código',
              errorText: _errorText,
            ),
            onSubmitted: (_) => !verifyDisabled ? _verify() : null,
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _cooldownLeft > 0
                    ? 'Reenviar en ${_cooldownLeft}s'
                    : _resends >= _kMaxResends
                    ? 'Reenvíos agotados'
                    : 'Puedes reenviar',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton(
                onPressed: canResend ? _resend : null,
                child: const Text('Reenviar código'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: verifyDisabled ? null : _verify,
          child: _verifying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verificar'),
        ),
      ],
    );
  }
}

// Utilidad simple para un ticker de 1 Hz sin depender de widgets externos
class Ticker {
  final void Function() onTick;
  Duration interval;
  bool _running = false;
  Ticker({required this.onTick, this.interval = const Duration(seconds: 1)});
  void start() {
    if (_running) return;
    _running = true;
    _tick();
  }

  void _tick() async {
    while (_running) {
      await Future.delayed(interval);
      onTick();
    }
  }

  void dispose() {
    _running = false;
  }
}
