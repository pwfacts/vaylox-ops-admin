import 'package:supabase_flutter/supabase_flutter.dart';
import 'access_profile_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signIn(String email, String password) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = response.user;
    if (user == null) return;

    // SaaS Check: Verify status
    try {
      // Post-Login Access Gate: Validates Platform Admin OR Tenant Membership
      // This will throw if the user has no organization or is suspended
      await getUserRole();
    } catch (e) {
      // 🔴 TASK 6: FAIL CLOSED (Authentication succeeded but Authorization failed)
      await signOut();

      // Preserve the specific error message from getUserRole
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo:
            'io.supabase.jdssaas://reset-password', // Deep link for mobile app
      );
    } catch (e) {
      // Re-throw with more context
      throw Exception('Failed to send password reset email: ${e.toString()}');
    }
  }

  Future<String?> getUserRole() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      // Delegate to Strict Access Profile Service
      final profile = await AccessProfileService().getAccessProfile();

      // Map to legacy role string for compatibility
      if (profile.isPlatformAdmin) {
        return 'super_admin';
      }
      return profile.role;
    } catch (e) {
      // Logic failure or Access Denied
      // AccessProfileService already logs security events
      rethrow;
    }
  }

  /// Returns true if the user has one of the allowed roles
  Future<bool> hasRole(List<String> allowedRoles) async {
    final role = await getUserRole();
    return role != null && allowedRoles.contains(role);
  }
}
