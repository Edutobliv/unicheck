from pathlib import Path
text = Path("lib/login_page.dart").read_text()
print(text.index("  }\n\n  @override"))
