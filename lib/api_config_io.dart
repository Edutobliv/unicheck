// Default to the deployed API on Render. Override with
//   --dart-define=API_BASE_URL=http://10.0.2.2:3000
// for local development on Android emulator, or your LAN IP for devices.
const String _kDefaultBase = 'https://unicheck-api.onrender.com';

String getBaseUrl() => _kDefaultBase;

