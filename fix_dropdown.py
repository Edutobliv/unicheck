from pathlib import Path
path = Path("lib/register_page.dart")
text = path.read_text()
needle = "DropdownButtonFormField<String>(\\n                      initialValue: selectedProgram,"
replacement = "DropdownButtonFormField<String>(\n                      initialValue: selectedProgram,"
if needle in text:
    text = text.replace(needle, replacement)
path.write_text(text)
