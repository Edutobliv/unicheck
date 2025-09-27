from pathlib import Path
path = Path("lib/login_page.dart")
text = path.read_text()
old = "    } catch (e) {\n      setState(() {\n        _error = 'Error de red: ${e.toString()} (Origen: red)';\n      });"
if old not in text:
    raise SystemExit('target catch not found')
new = "    } on TimeoutException catch (_) {\n      _startRetryCountdown();\n      return;\n    } catch (e) {\n      setState(() {\n        _error = 'Error de red: ${e.toString()} (Origen: red)';\n      });"
text = text.replace(old, new, 1)
path.write_text(text)
