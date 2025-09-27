from pathlib import Path
path = Path('lib/login_page.dart')
text = path.read_text(encoding='utf-8')
if "import 'dart:async';" not in text:
    text = "import 'dart:async';\n" + text
path.write_text(text, encoding='utf-8')
