import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  try {
    print('🚀 Testing Supabase connection...');
    
    await Supabase.initialize(
      url: 'https://fcpbexqyyzdvbiwplmjt.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjcGJleHF5eXpkdmJpd3BsbWp0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzI4NTY4MDYsImV4cCI6MjA0ODQzMjgwNn0.JdM6zVeuwTNxLGPMEhPJqNzrPSJDnMqTT_mI1FSTgYg',
    );
    print('✅ Supabase initialization successful!');
    
    // Test basic connection
    final response = await Supabase.instance.client
        .from('guards')
        .select('count')
        .count(CountOption.exact);
    print('✅ Database connection test successful!');
    print('Guards table accessible. Count query executed successfully.');
    
    // Test auth connection
    final user = Supabase.instance.client.auth.currentUser;
    print('Current user: ${user?.id ?? 'Not authenticated'}');
    
    print('🎉 All Supabase tests passed!');
    
  } catch (e) {
    print('❌ Supabase connection error: $e');
    print('Please check:');
    print('1. Supabase URL is correct');
    print('2. Supabase anon key is valid');
    print('3. Guards table exists in your database');
    print('4. Network connection is stable');
  }
}