from pathlib import Path
import re
path = Path('lib/login_page.dart')
text = path.read_text(encoding='utf-8')
pattern = re.compile(r"\n\s*void _startRetryCountdown\(\) \{[\s\S]*?\n\s*}\n")
matches = list(pattern.finditer(text))
if not matches:
    raise SystemExit('no retry method found')
# Keep first, remove subsequent
if len(matches) > 1:
    parts = []
    last_end = 0
    for idx, match in enumerate(matches):
        if idx == 0:
            parts.append(text[last_end:match.end()])
        else:
            parts.append(text[last_end:match.start()])
            last_end = match.end()
    parts.append(text[last_end:])
    text = ''.join(parts)
path.write_text(text, encoding='utf-8')
