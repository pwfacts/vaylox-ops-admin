// Foundation Rules - Single Company System
import 'supabase_config.dart';

const String defaultCompanyId = 'c0a80101-b632-4e6a-9818-1d2f9d5e3f4b';

// Supabase Configuration - Using SupabaseConfig for flexible environment switching
// Use SupabaseConfig for dynamic environment switching
String get supabaseUrl => SupabaseConfig.supabaseUrl;
String get supabaseAnonKey => SupabaseConfig.supabaseAnonKey;

// ImageKit Configuration
const String imagekitUrlEndpoint = 'https://ik.imagekit.io/prabhatworldtech/';
const String imagekitPublicKey = 'public_J3YXmP/aWgPakWpXeq5ZynKNS9w=';

class AppConstants {
  static const String companyId = defaultCompanyId;
}
