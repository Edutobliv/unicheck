from pathlib import Path
path = Path('lib/login_page.dart')
text = path.read_text(encoding='utf-8')
old = "  Future<void> _login() async {\n    FocusScope.of(context).unfocus();\n    setState(() {\n      _loading = true;\n      _error = null;\n    });\n"
new = "  Future<void> _login() async {\n    FocusScope.of(context).unfocus();\n    _retryTimer?.cancel();\n    _retryTimer = null;\n    _retrySeconds = 0;\n    setState(() {\n      _loading = true;\n      _error = null;\n    });\n"
if old not in text:
    raise SystemExit('login header snippet not found')
text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
