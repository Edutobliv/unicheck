class SupabaseConfig {
  // Provide via --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_ANON_KEY=...
  static String get url {
    const fromEnv = String.fromEnvironment('SUPABASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    // Fallback placeholder. Replace for local runs if you prefer.
    return 'https://kiuutfehtetjsplqxtsi.supabase.co';
  }

  static String get anonKey {
    const fromEnv = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (fromEnv.isNotEmpty) return fromEnv;
    // Fallback placeholder. Replace for local runs if you prefer.
    return 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtpdXV0ZmVodGV0anNwbHF4dHNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc4Njk4MDMsImV4cCI6MjA3MzQ0NTgwM30.jodUg6PN_SB4RUMK143PI1ZuIE2CnlG53u0P4s0qlbw';
  }

  static bool get isConfigured =>
      url.startsWith('http') && !anonKey.startsWith('YOUR_') && anonKey.length > 20;
}
