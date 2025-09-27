from pathlib import Path
path = Path("lib/login_page.dart")
text = path.read_text(encoding='utf-8')
first = text.find("import 'dart:async';")
second = text.find("import 'dart:async';", first + 1)
if second != -1:
    text = text[:second]
path.write_text(text, encoding='utf-8')
