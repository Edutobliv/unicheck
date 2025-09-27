from pathlib import Path
path = Path('lib/login_page.dart')
text = path.read_text(encoding='utf-8')
marker = "class _LoginPageState extends State<LoginPage> {\n"
if marker not in text:
    raise SystemExit('class marker not found')
insertion = "  Timer? _retryTimer;\n  int _retrySeconds = 0;\n"
if insertion.strip() not in text:
    text = text.replace(marker, marker + insertion)
path.write_text(text, encoding='utf-8')
