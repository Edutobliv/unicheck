from pathlib import Path
path = Path('lib/login_page.dart')
text = path.read_text(encoding='utf-8')
marker = "  @override\n  Widget build(BuildContext context) {\n"
if marker not in text:
    raise SystemExit('build marker not found')
method = "  void _startRetryCountdown() {\n    _retryTimer?.cancel();\n    _retrySeconds = 30;\n\n    void updateMessage() {\n      _error =\n          'Estamos iniciando el servidor... nuevo intento en \\${_retrySeconds}s';\n    }\n\n    setState(() {\n      _loading = false;\n      updateMessage();\n    });\n\n    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {\n      if (!mounted) {\n        timer.cancel();\n        return;\n      }\n\n      if (_retrySeconds <= 1) {\n        timer.cancel();\n        _retrySeconds = 0;\n        setState(() {\n          updateMessage();\n        });\n        _login();\n      } else {\n        setState(() {\n          _retrySeconds -= 1;\n          updateMessage();\n        });\n      }\n    });\n  }\n\n"
if method.strip() in text:
    pass
else:
    text = text.replace(marker, method + marker)
path.write_text(text, encoding='utf-8')
