from pathlib import Path
path = Path("lib/login_page.dart")
text = path.read_text()
insertion = "  void _startRetryCountdown() {\n    _retryTimer?.cancel();\n    _retrySeconds = 30;\n\n    setState(() {\n      _loading = false;\n      _error = 'Estamos iniciando el servidor... reintento en ${_retrySeconds} s';\n    });\n\n    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {\n      if (!mounted) {\n        timer.cancel();\n        return;\n      }\n\n      if (_retrySeconds <= 1) {\n        timer.cancel();\n        _retrySeconds = 0;\n        setState(() {\n          _error = 'Estamos iniciando el servidor... reintento en ${_retrySeconds} s';\n        });\n        _login();\n      } else {\n        setState(() {\n          _retrySeconds -= 1;\n          _error = 'Estamos iniciando el servidor... reintento en ${_retrySeconds} s';\n        });\n      }\n    });\n  }\n\n"
if "_startRetryCountdown" not in text:
    text = text.replace("  }\n\n  @override", "  }\n\n" + insertion + "  @override", 1)
path.write_text(text)
