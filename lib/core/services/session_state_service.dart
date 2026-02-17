import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'secure_storage_service.dart';

/// Session states for operational reliability
enum SessionState {
  verified, // Full access
  restricted, // Attendance only (after password change, unit transfer)
  recovery, // Offline mode with cached credentials
}

/// Operational permissions
enum Operation {
  attendancePunch,
  viewDuty,
  approvals,
  edits,
  adminActions,
  coverageOverride,
  realTimeData,
}

/// Session State Service
/// Manages session states independent of Supabase JWT
/// Supports offline and restricted operations
class SessionStateService {
  final _supabase = Supabase.instance.client;
  final _storage = SecureStorageService();

  static const String _sessionStateKey = 'session_state';
  static const String _cachedPinHashKey = 'cached_pin_hash';
  static const String _offlineQueueKey = 'offline_attendance_queue';

  // ============================================
  // STATE MANAGEMENT
  // ============================================

  /// Get current session state
  Future<SessionState> getCurrentState() async {
    try {
      final profileId = await _getProfileId();
      final deviceFingerprint = await _getDeviceFingerprint();

      final response = await _supabase
          .from('workforce_session_states')
          .select('state')
          .eq('profile_id', profileId)
          .eq('device_fingerprint', deviceFingerprint)
          .maybeSingle();

      if (response == null) {
        return SessionState.verified; // Default state
      }

      final stateStr = response['state'] as String;
      return _parseState(stateStr);
    } catch (e) {
      // If offline or error, check local cache
      final cachedState = await _storage.getString(_sessionStateKey);
      return _parseState(cachedState ?? 'VERIFIED');
    }
  }

  /// Check if operation is allowed
  Future<OperationCheckResult> canPerformOperation(Operation operation) async {
    try {
      final profileId = await _getProfileId();
      final deviceFingerprint = await _getDeviceFingerprint();

      final response = await _supabase.rpc('check_operation_allowed', params: {
        'p_profile_id': profileId,
        'p_device_fingerprint': deviceFingerprint,
        'p_operation': _operationToString(operation),
      });

      return OperationCheckResult(
        allowed: response['allowed'] as bool,
        state: _parseState(response['state'] as String),
        reason: response['reason'] as String?,
        message: response['message'] as String?,
      );
    } catch (e) {
      // If offline, use local rules
      final state = await getCurrentState();
      return _getOfflineOperationPermission(operation, state);
    }
  }

  /// Update session state
  Future<void> transitionState({
    required SessionState newState,
    String? reason,
    DateTime? restrictedUntil,
    Map<String, dynamic>? shiftContext,
  }) async {
    final profileId = await _getProfileId();
    final deviceFingerprint = await _getDeviceFingerprint();

    try {
      await _supabase.rpc('update_session_state', params: {
        'p_profile_id': profileId,
        'p_device_fingerprint': deviceFingerprint,
        'p_new_state': _stateToString(newState),
        'p_reason': reason,
        'p_restricted_until': restrictedUntil?.toIso8601String(),
        'p_shift_context': shiftContext,
      });

      // Cache state locally
      await _storage.saveString(_sessionStateKey, _stateToString(newState));
    } catch (e) {
      // If offline, cache locally only
      await _storage.saveString(_sessionStateKey, _stateToString(newState));
      rethrow;
    }
  }

  /// Auto-upgrade session state (e.g., RESTRICTED → VERIFIED after shift end)
  Future<bool> tryUpgradeState() async {
    try {
      final profileId = await _getProfileId();
      final deviceFingerprint = await _getDeviceFingerprint();

      final response =
          await _supabase.rpc('auto_upgrade_session_state', params: {
        'p_profile_id': profileId,
        'p_device_fingerprint': deviceFingerprint,
      });

      if (response['upgraded'] == true) {
        final newState = _parseState(response['current_state'] as String);
        await _storage.saveString(_sessionStateKey, _stateToString(newState));
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  // ============================================
  // OFFLINE CREDENTIAL CACHING
  // ============================================

  /// Cache PIN hash for offline verification
  Future<void> cacheCredentialHash(String pin) async {
    final pinHash = _hashPin(pin);
    final profileId = await _getProfileId();
    final deviceFingerprint = await _getDeviceFingerprint();

    try {
      // Store in database
      await _supabase.rpc('cache_offline_credential', params: {
        'p_profile_id': profileId,
        'p_device_fingerprint': deviceFingerprint,
        'p_pin_hash': pinHash,
        'p_expiry_days': 7,
      });

      // Also cache locally
      await _storage.saveString(_cachedPinHashKey, pinHash);
      await _storage.saveString('${_cachedPinHashKey}_expires',
          DateTime.now().add(const Duration(days: 7)).toIso8601String());
    } catch (e) {
      // If offline, cache locally only
      await _storage.saveString(_cachedPinHashKey, pinHash);
      await _storage.saveString('${_cachedPinHashKey}_expires',
          DateTime.now().add(const Duration(days: 7)).toIso8601String());
    }
  }

  /// Verify PIN against cached hash (offline mode)
  Future<OfflineVerificationResult> verifyOfflinePin(String pin) async {
    final profileId = await _getProfileId();
    final deviceFingerprint = await _getDeviceFingerprint();

    try {
      // Try server verification first
      final response =
          await _supabase.rpc('verify_offline_credential', params: {
        'p_profile_id': profileId,
        'p_device_fingerprint': deviceFingerprint,
        'p_pin': pin,
      });

      if (response['success'] == true) {
        return OfflineVerificationResult(
          verified: true,
          verificationCount: response['verification_count'] as int,
          remainingVerifications: response['remaining_verifications'] as int,
        );
      } else {
        return OfflineVerificationResult(
          verified: false,
          error: response['error'] as String?,
          message: response['message'] as String?,
        );
      }
    } catch (e) {
      // Truly offline - use local cache
      return await _verifyLocalCachedPin(pin);
    }
  }

  /// Check if cached hash is still valid
  Future<bool> isCachedHashValid() async {
    final expiresStr = await _storage.getString('${_cachedPinHashKey}_expires');
    if (expiresStr == null) return false;

    final expires = DateTime.parse(expiresStr);
    return expires.isAfter(DateTime.now());
  }

  // ============================================
  // OFFLINE ATTENDANCE QUEUE
  // ============================================

  /// Queue attendance punch for later sync
  Future<String> queueAttendancePunch({
    required Map<String, dynamic> attendanceData,
    required String operationType,
    bool offlinePinVerified = false,
  }) async {
    final profileId = await _getProfileId();
    final deviceFingerprint = await _getDeviceFingerprint();

    try {
      // Try to queue on server
      final response = await _supabase.rpc('queue_offline_attendance', params: {
        'p_profile_id': profileId,
        'p_device_fingerprint': deviceFingerprint,
        'p_attendance_data': attendanceData,
        'p_operation_type': operationType,
        'p_offline_pin_verified': offlinePinVerified,
      });

      return response['queue_id'] as String;
    } catch (e) {
      // Truly offline - queue locally
      return await _queueLocalAttendance(
          attendanceData, operationType, offlinePinVerified);
    }
  }

  /// Sync pending attendance operations
  Future<SyncResult> syncPendingOperations() async {
    // Get local queue
    final queueJson = await _storage.getString(_offlineQueueKey);
    if (queueJson == null) {
      return SyncResult(synced: 0, failed: 0);
    }

    final queue = jsonDecode(queueJson) as List<dynamic>;
    int synced = 0;
    int failed = 0;

    final newQueue = <Map<String, dynamic>>[];

    for (final item in queue) {
      try {
        final attendanceData = item['attendance_data'] as Map<String, dynamic>;
        final operationType = item['operation_type'] as String;

        // Process based on operation type
        if (operationType == 'CHECK_IN' || operationType == 'CHECK_OUT') {
          await _supabase.from('attendance').insert(attendanceData);
        } else if (operationType == 'MARK_ARRIVAL') {
          await _supabase.from('guard_arrivals').insert(attendanceData);
        }

        synced++;
      } catch (e) {
        // Keep in queue for retry
        newQueue.add(item as Map<String, dynamic>);
        failed++;
      }
    }

    // Update local queue
    if (newQueue.isEmpty) {
      await _storage.deleteKey(_offlineQueueKey);
    } else {
      await _storage.saveString(_offlineQueueKey, jsonEncode(newQueue));
    }

    return SyncResult(synced: synced, failed: failed);
  }

  /// Get pending sync count
  Future<int> getPendingSyncCount() async {
    final queueJson = await _storage.getString(_offlineQueueKey);
    if (queueJson == null) return 0;

    final queue = jsonDecode(queueJson) as List<dynamic>;
    return queue.length;
  }

  // ============================================
  // STATE CHECKERS (Convenience)
  // ============================================

  Future<bool> get isVerified async =>
      (await getCurrentState()) == SessionState.verified;
  Future<bool> get isRestricted async =>
      (await getCurrentState()) == SessionState.restricted;
  Future<bool> get isRecovery async =>
      (await getCurrentState()) == SessionState.recovery;

  Future<bool> get canApprove async =>
      (await canPerformOperation(Operation.approvals)).allowed;

  Future<bool> get canPunchAttendance async =>
      (await canPerformOperation(Operation.attendancePunch)).allowed;

  // ============================================
  // PRIVATE HELPERS
  // ============================================

  Future<String> _getProfileId() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final response = await _supabase
        .from('workforce_profiles')
        .select('id')
        .eq('linked_auth_user', user.id)
        .single();

    return response['id'] as String;
  }

  Future<String> _getDeviceFingerprint() async {
    // Use stored device fingerprint
    return await _storage.getString('device_fingerprint') ?? 'unknown';
  }

  SessionState _parseState(String state) {
    switch (state.toUpperCase()) {
      case 'VERIFIED':
        return SessionState.verified;
      case 'RESTRICTED':
        return SessionState.restricted;
      case 'RECOVERY':
        return SessionState.recovery;
      default:
        return SessionState.verified;
    }
  }

  String _stateToString(SessionState state) {
    switch (state) {
      case SessionState.verified:
        return 'VERIFIED';
      case SessionState.restricted:
        return 'RESTRICTED';
      case SessionState.recovery:
        return 'RECOVERY';
    }
  }

  String _operationToString(Operation operation) {
    switch (operation) {
      case Operation.attendancePunch:
        return 'attendance_punch';
      case Operation.viewDuty:
        return 'view_duty';
      case Operation.approvals:
        return 'approvals';
      case Operation.edits:
        return 'edits';
      case Operation.adminActions:
        return 'admin_actions';
      case Operation.coverageOverride:
        return 'coverage_override';
      case Operation.realTimeData:
        return 'real_time_data';
    }
  }

  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  Future<OfflineVerificationResult> _verifyLocalCachedPin(String pin) async {
    final cachedHash = await _storage.getString(_cachedPinHashKey);
    if (cachedHash == null) {
      return OfflineVerificationResult(
        verified: false,
        error: 'NO_CACHED_CREDENTIAL',
      );
    }

    final isValid = await isCachedHashValid();
    if (!isValid) {
      return OfflineVerificationResult(
        verified: false,
        error: 'CREDENTIAL_EXPIRED',
      );
    }

    final pinHash = _hashPin(pin);
    final verified = pinHash == cachedHash;

    if (verified) {
      // Increment local verification count
      final countStr =
          await _storage.getString('offline_verification_count') ?? '0';
      final count = int.parse(countStr);
      await _storage.saveString(
          'offline_verification_count', (count + 1).toString());

      return OfflineVerificationResult(
        verified: true,
        verificationCount: count + 1,
        remainingVerifications: 10 - (count + 1),
      );
    } else {
      return OfflineVerificationResult(verified: false, error: 'INVALID_PIN');
    }
  }

  Future<String> _queueLocalAttendance(
    Map<String, dynamic> attendanceData,
    String operationType,
    bool offlinePinVerified,
  ) async {
    final queueJson = await _storage.getString(_offlineQueueKey);
    final queue =
        queueJson != null ? jsonDecode(queueJson) as List<dynamic> : [];

    final queueId = DateTime.now().millisecondsSinceEpoch.toString();

    queue.add({
      'queue_id': queueId,
      'attendance_data': attendanceData,
      'operation_type': operationType,
      'offline_pin_verified': offlinePinVerified,
      'queued_at': DateTime.now().toIso8601String(),
    });

    await _storage.saveString(_offlineQueueKey, jsonEncode(queue));
    return queueId;
  }

  OperationCheckResult _getOfflineOperationPermission(
    Operation operation,
    SessionState state,
  ) {
    // Offline rules
    final allowedInRestricted = [Operation.attendancePunch, Operation.viewDuty];
    final allowedInRecovery = [Operation.attendancePunch, Operation.viewDuty];

    switch (state) {
      case SessionState.verified:
        return OperationCheckResult(allowed: true, state: state);
      case SessionState.restricted:
        return OperationCheckResult(
          allowed: allowedInRestricted.contains(operation),
          state: state,
          message: 'Please re-authenticate to perform this action',
        );
      case SessionState.recovery:
        return OperationCheckResult(
          allowed: allowedInRecovery.contains(operation),
          state: state,
          message: 'This action requires online connection',
        );
    }
  }
}

/// Result of operation permission check
class OperationCheckResult {
  final bool allowed;
  final SessionState state;
  final String? reason;
  final String? message;

  OperationCheckResult({
    required this.allowed,
    required this.state,
    this.reason,
    this.message,
  });
}

/// Result of offline PIN verification
class OfflineVerificationResult {
  final bool verified;
  final int? verificationCount;
  final int? remainingVerifications;
  final String? error;
  final String? message;

  OfflineVerificationResult({
    required this.verified,
    this.verificationCount,
    this.remainingVerifications,
    this.error,
    this.message,
  });
}

/// Result of sync operation
class SyncResult {
  final int synced;
  final int failed;

  SyncResult({required this.synced, required this.failed});

  bool get hasFailures => failed > 0;
  bool get allSynced => failed == 0 && synced > 0;
}
