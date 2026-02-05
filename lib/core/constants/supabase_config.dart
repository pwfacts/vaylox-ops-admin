// This file contains environment-specific configuration
// You can switch between local and remote Supabase easily

class SupabaseConfig {
  // Get from environment variables (for production) or fallback to hardcoded (for development)
  static String get supabaseUrl {
    // Check if running on web and environment variable exists
    const envUrl = String.fromEnvironment('VITE_SUPABASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }
    
    // Fallback to configuration based on environment
    return useLocalSupabase ? localUrl : remoteUrl;
  }
  
  static String get supabaseAnonKey {
    // Check if running on web and environment variable exists
    const envKey = String.fromEnvironment('VITE_SUPABASE_ANON_KEY');
    if (envKey.isNotEmpty) {
      return envKey;
    }
    
    // Fallback to configuration based on environment
    return useLocalSupabase ? localAnonKey : remoteAnonKey;
  }

  // Remote Supabase (Production/Staging) - Use environment variables for actual values
  static const String remoteUrl = 'https://fcpbexqyyzdvbiwplmjt.supabase.co';
  static const String remoteAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjcGJleHF5eXpkdmJpd3BsbWp0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk2NjU2OTYsImV4cCI6MjA4NTI0MTY5Nn0.4PQByF7K7H0kTGgYxchdVJgqy-5pzGTC_FqGJQ50muw';
  
  // Local Supabase (Development)
  static const String localUrl = 'http://localhost:54321';
  static const String localAnonKey = 'LOCAL_DEVELOPMENT_KEY_PLACEHOLDER';
  
  // Switch between environments
  static const bool useLocalSupabase = false; // Set to true for local development
}