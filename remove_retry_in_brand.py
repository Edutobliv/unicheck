from pathlib import Path
import re
path = Path('lib/login_page.dart')
text = path.read_text(encoding='utf-8')
pattern = re.compile(r"(class _BrandGlyph[\s\S]*?){\s*void _startRetryCountdown\(\) \{[\s\S]*?\n\s*}\n", re.MULTILINE)
text, _ = pattern.subn(lambda m: m.group(1) + '{\n', text, count=1)
path.write_text(text, encoding='utf-8')
