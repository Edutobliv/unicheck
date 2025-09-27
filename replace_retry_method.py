from pathlib import Path
import re
path = Path('lib/login_page.dart')
text = path.read_text(encoding='utf-8')
pattern = re.compile(r"  }\r\n    setState\(\) \{[\s\S]*?    });\r\n  }\r\n\r\n  @override")
match = pattern.search(text)
if not match:
    raise SystemExit('retry block not found for replacement')
replacement = "  }\r\n\r\n  void _startRetryCountdown() {\r\n    _retryTimer?.cancel();\r\n    _retrySeconds = 30;\r\n\r\n    void updateMessage() {\r\n      _error =\r\n          'Estamos iniciando el servidor... nuevo intento en ${_retrySeconds} s';\r\n    }\r\n\r\n    setState(() {\r\n      _loading = false;\r\n      updateMessage();\r\n    });\r\n\r\n    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {\r\n      if (!mounted) {\r\n        timer.cancel();\r\n        return;\r\n      }\r\n\r\n      if (_retrySeconds <= 1) {\r\n        timer.cancel();\r\n        _retrySeconds = 0;\r\n        setState(() {\r\n          updateMessage();\r\n        });\r\n        _login();\r\n      } else {\r\n        setState(() {\r\n          _retrySeconds -= 1;\r\n          updateMessage();\r\n        });\r\n      }\r\n    });\r\n  }\r\n\r\n  @override"
text = text[:match.start()] + replacement + text[match.end():]
path.write_text(text, encoding='utf-8')
