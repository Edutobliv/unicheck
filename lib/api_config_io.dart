import 'dart:io';

String getBaseUrl() {
  // Android emulator reaches the host machine via 10.0.2.2.
  // For a physical Android device, pass --dart-define=API_BASE_URL with your PC IP.
  if (Platform.isAndroid) return 'http://10.0.2.2:3000';
  return 'http://localhost:3000';
}

