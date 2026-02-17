import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import 'access_profile.dart';

class AccessProfileService {
  final SupabaseClient _client = Supabase.instance.client;
  final _logger = Logger();

  Future<AccessProfile> getAccessProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw 'User not authenticated';
    }

    // 1. Check Platform Admin (Strict Table Check)
    bool isPlatformAdmin = false;
    try {
      final platformAdminRes = await _client
          .from('platform_admins')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();
      isPlatformAdmin = platformAdminRes != null;
    } catch (e) {
      // RLS might block access for non-admins, safest to assume false
      _logger.w('Platform Check Warning: $e');
      isPlatformAdmin = false;
    }

    // 2. Fetch User Profile & Membership
    final membershipRes = await _client
        .from('organization_users')
        .select('role, organization_id, users(id, full_name, status)')
        .eq('user_id', user.id)
        .limit(1)
        .maybeSingle();

    if (membershipRes == null) {
      // Check if user exists at all in users table (e.g. platform admin with no org)

      if (isPlatformAdmin) {
        _logAccessCheck(
          user: user,
          organizationId: null,
          role: 'super_admin',
          isPlatformAdmin: true,
          status: 'SUCCESS_PLATFORM_OVERRIDE',
        );
        return AccessProfile(
          userId: user.id,
          email: user.email,
          organizationId: null, // Global Scope
          role: 'super_admin',
          isPlatformAdmin: true,
        );
      }

      _logAccessCheck(
        user: user,
        organizationId: null,
        role: 'unknown',
        isPlatformAdmin: isPlatformAdmin,
        status: 'FAILED_NO_PROFILE',
      );
      throw 'Access Denied: User profile not found with any organization';
    }

    final organizationId = membershipRes['organization_id'] as String?;
    final role = membershipRes['role'] as String? ?? 'guest';
    final userData = membershipRes['users'] as Map<String, dynamic>?;
    final status = userData?['status'] as String? ?? 'UNKNOWN';

    // 3. Status Check
    if (status != 'ACTIVE' && status != 'active' && !isPlatformAdmin) {
      _logAccessCheck(
        user: user,
        organizationId: organizationId,
        role: role,
        isPlatformAdmin: isPlatformAdmin,
        status: 'FAILED_SUSPENDED_$status',
      );
      throw 'Access Denied: Account is $status. Contact support.';
    }

    // 4. Organization ID Check
    if (!isPlatformAdmin && organizationId == null) {
      _logAccessCheck(
        user: user,
        organizationId: null,
        role: role,
        isPlatformAdmin: isPlatformAdmin,
        status: 'FAILED_NO_ORG',
      );
      throw 'Access Denied: Organization not provisioned.';
    }

    // 5. Success Log
    _logAccessCheck(
      user: user,
      organizationId: organizationId,
      role: role,
      isPlatformAdmin: isPlatformAdmin,
      status: 'SUCCESS',
    );

    return AccessProfile(
      userId: user.id,
      email: user.email,
      organizationId: organizationId,
      role: role,
      isPlatformAdmin: isPlatformAdmin,
    );
  }

  void _logAccessCheck({
    required User user,
    required String? organizationId,
    required String role,
    required bool isPlatformAdmin,
    required String status,
  }) {
    // TASK 6: LOGIN SECURITY LOG
    final timestamp = DateTime.now().toIso8601String();
    _logger.i(
        '[SECURITY_AUDIT] Time:$timestamp User:${user.id} Email:${user.email} Role:$role IsPlatformAdmin:$isPlatformAdmin Organization:$organizationId Status:$status');

    if (organizationId == null &&
        !isPlatformAdmin &&
        status != 'FAILED_NO_PROFILE') {
      _logger.w(
          '[SECURITY_ALERT] Tenant User attempting login without Organization ID!');
    }
  }
}
