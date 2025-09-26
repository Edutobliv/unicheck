from pathlib import Path
lines = Path(r"c:\\Unicheck\\lib\\register_page.dart").read_text(encoding='utf-8').splitlines()
for idx, line in enumerate(lines, 1):
    if "Future<void> _submit()" in line:
        print('submit', idx)
    if "if (!mounted) return;" in line and 'source == null' not in lines[idx] and 'photo' not in lines[idx-2]:
        print('mounted', idx)
    if "initialValue: _selectedProgram" in line:
        print('dropdown', idx)
