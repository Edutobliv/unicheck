import 'api_config_web.dart' if (dart.library.io) 'api_config_io.dart';

class ApiConfig {
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return getBaseUrl();
  }
}
