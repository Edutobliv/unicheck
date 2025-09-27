from pathlib import Path
path = Path("lib/login_page.dart")
text = path.read_text()
text = text.replace('${_retrySeconds}', '$_retrySeconds')
path.write_text(text)
