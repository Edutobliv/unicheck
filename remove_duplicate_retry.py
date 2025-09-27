from pathlib import Path
path = Path('lib/login_page.dart')
text = path.read_text(encoding='utf-8')
import re
pattern = r"\n\s*void _startRetryCountdown\(\) \{[\s\S]*?\n\s*}\n\n"
new_text, count = re.subn(pattern, '\n', text, count=1)
if count == 0:
    raise SystemExit('duplicate method not found in HeroColumn')
path.write_text(new_text, encoding='utf-8')
