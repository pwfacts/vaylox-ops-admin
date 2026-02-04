// This file contains environment-specific configuration
// You can switch between local and remote Supabase easily

class SupabaseConfig {
  // Get from environment variables (for production) or fallback to hardcoded (for development)
  static String get supabaseUrl {
    // Check if running on web and environment variable exists
    const envUrl = String.fromEnvironment('SUPABASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }
    
    // Fallback to configuration based on environment
    return useLocalSupabase ? localUrl : remoteUrl;
  }
  
  static String get supabaseAnonKey {
    // Check if running on web and environment variable exists
    const envKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (envKey.isNotEmpty) {
      return envKey;
    }
    
    // Fallback to configuration based on environment
    return useLocalSupabase ? localAnonKey : remoteAnonKey;
  }

  // Remote Supabase (Production/Staging)
  static const String remoteUrl = 'https://fcpbexqyyzdvbiwplmjt.supabase.co';
  static const String remoteAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjcGJleHF5eXpkdmJpd3BsbWp0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzI4NTY4MDYsImV4cCI6MjA0ODQzMjgwNn0.JdM6zVeuwTNxLGPMEhPJqNzrPSJDnMqTT_mI1FSTgYg';
  
  // Local Supabase (Development)
  static const String localUrl = 'http://localhost:54321';
  static const String localAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxvY2FsaG9zdCIsInJvbGUiOiJhbm9uIiwiaWF0IjoxNjQ5Nzc2MDAwfQ.SqnLgpw5Z-M0J-9lJ8v3J8X1Jv5K5K5K5K5K5K5';
  
  // Switch between environments
  static const bool useLocalSupabase = false; // Set to true for local development
}