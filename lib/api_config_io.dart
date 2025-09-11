import 'dart:io';

String getBaseUrl() {
  // Android emulator reaches host via 10.0.2.2; others use localhost
  if (Platform.isAndroid) return 'http://10.0.2.2:3000';
  return 'http://localhost:3000';
}

