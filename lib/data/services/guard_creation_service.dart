import 'supabase_service.dart';
import '../models/guard_model.dart';
import 'package:logger/logger.dart';

class GuardCreationService {
  final _client = SupabaseService.client;
  final _logger = Logger();

  /// Create guard using Edge Function (handles auth user + email)
  Future<GuardCreationResult> createGuardWithAuth({
    required Guard guard,
    bool sendPasswordEmail = true,
  }) async {
    try {
      _logger.i('Creating guard with auth via Edge Function: ${guard.email}');

      final response = await _client.functions.invoke(
        'create-guard',
        body: {
          'guardData': guard.toJson(),
          'sendPasswordEmail': sendPasswordEmail,
        },
      );

      if (response.status != 200) {
        throw Exception('Edge Function error: ${response.data}');
      }

      final data = response.data as Map<String, dynamic>;

      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Unknown error');
      }

      final result = data['data'] as Map<String, dynamic>;

      _logger.i('✅ Guard created successfully: ${data['message']}');

      return GuardCreationResult(
        guard: Guard.fromJson(result['guard'] as Map<String, dynamic>),
        authUserId: result['authUserId'] as String,
        emailSent: result['emailSent'] as bool,
        emailError: result['emailError'] as String?,
        temporaryPassword: result['temporaryPassword'] as String?,
        message: data['message'] as String,
      );
    } catch (e) {
      _logger.e('Error creating guard:', error: e);
      rethrow;
    }
  }

  /// Resend password email for existing guard
  Future<bool> resendPasswordEmail({
    required String guardEmail,
    required String guardName,
    required String password,
    String? guardCode,
  }) async {
    try {
      _logger.i('Resending password email to: $guardEmail');

      final response = await _client.functions.invoke(
        'send-guard-credentials',
        body: {
          'email': guardEmail,
          'fullName': guardName,
          'password': password,
          'guardCode': guardCode,
        },
      );

      if (response.status != 200) {
        throw Exception('Failed to send email: ${response.data}');
      }

      final data = response.data as Map<String, dynamic>;
      return data['success'] == true;
    } catch (e) {
      _logger.e('Error resending email:', error: e);
      return false;
    }
  }

  /// Get temporary password for a guard (admin/field officer only)
  Future<String?> getTemporaryPassword(String userId) async {
    try {
      final response = await _client
          .from('temporary_passwords')
          .select('encrypted_password, expires_at')
          .eq('user_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      // Check if expired
      final expiresAt = DateTime.parse(response['expires_at'] as String);
      if (expiresAt.isBefore(DateTime.now())) {
        return null;
      }

      // Decode password (simple base64 decoding - use proper crypto in production)
      final encoded = response['encrypted_password'] as String;
      return String.fromCharCodes(
        Uri.decodeComponent(encoded).codeUnits,
      );
    } catch (e) {
      _logger.e('Error fetching temporary password:', error: e);
      return null;
    }
  }

  /// Mark password as viewed
  Future<void> markPasswordAsViewed(String userId) async {
    try {
      await _client
          .from('temporary_passwords')
          .update({
            'viewed_at': DateTime.now().toIso8601String(),
            'viewed_by': _client.auth.currentUser?.id,
          })
          .eq('user_id', userId)
          .eq('is_active', true);
    } catch (e) {
      _logger.w('Failed to mark password as viewed:', error: e);
    }
  }
}

class GuardCreationResult {
  final Guard guard;
  final String authUserId;
  final bool emailSent;
  final String? emailError;
  final String? temporaryPassword;
  final String message;

  GuardCreationResult({
    required this.guard,
    required this.authUserId,
    required this.emailSent,
    this.emailError,
    this.temporaryPassword,
    required this.message,
  });

  bool get needsManualPasswordSharing =>
      !emailSent && temporaryPassword != null;
}
