from pathlib import Path
path = Path('lib/login_page.dart')
text = path.read_text(encoding='utf-8')
old = "    } catch (e) {\n      setState(() {\n        _error = 'Error de red: ${e.toString()} (Origen: red)';\n      });\n    } finally {"
new = "    } on TimeoutException catch (_) {\n      _startRetryCountdown();\n      return;\n    } catch (e) {\n      setState(() {\n        _error = 'Error de red: ${e.toString()} (Origen: red)';\n      });\n    } finally {"
if old not in text:
    raise SystemExit('catch block not found')
text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
