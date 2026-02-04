import 'package:supabase_flutter/supabase_flutter.dart';

// Test Supabase connection
void main() async {
  print('🚀 Starting Supabase connection test...');
  
  try {
    // Initialize Supabase
    print('📡 Initializing Supabase...');
    await Supabase.initialize(
      url: 'https://fcpbexqyyzdvbiwplmjt.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjcGJleHF5eXpkdmJpd3BsbWp0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzI4NTY4MDYsImV4cCI6MjA0ODQzMjgwNn0.JdM6zVeuwTNxLGPMEhPJqNzrPSJDnMqTT_mI1FSTgYg',
    );
    print('✅ Supabase initialization successful!');
    
    // Test basic connection
    print('🔍 Testing database connection...');
    final client = Supabase.instance.client;
    
    // Try to access a simple endpoint
    final response = await client
        .from('guards')
        .select('*')
        .limit(1);
    
    print('✅ Database connection successful!');
    print('Sample response: $response');
    
    // Test auth status
    final user = client.auth.currentUser;
    print('Current user: ${user?.id ?? 'Not authenticated (expected)'}');
    
    print('🎉 All Supabase tests passed! Your connection is working.');
    
  } catch (e, stackTrace) {
    print('❌ Supabase test failed: $e');
    print('Stack trace: $stackTrace');
    
    // Common troubleshooting
    print('\n🔧 Troubleshooting:');
    print('1. Check if the Supabase URL is correct');
    print('2. Verify the anon key is valid');
    print('3. Ensure the guards table exists');
    print('4. Check network connectivity');
    print('5. Verify Row Level Security (RLS) policies');
  }
}