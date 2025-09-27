from pathlib import Path
import re
path = Path('lib/login_page.dart')
text = path.read_text(encoding='utf-8')
# Remove retry method inside HeroColumn if present
pattern = re.compile(r"(class _HeroColumn[\s\S]*?){\s*void _startRetryCountdown\(\) \{[\s\S]*?\n\s*}\n", re.MULTILINE)
text, count = pattern.subn(lambda m: m.group(1) + '{\n', text, count=1)
path.write_text(text, encoding='utf-8')
