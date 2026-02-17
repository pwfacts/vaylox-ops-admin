import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'session_state_service.dart';
import 'secure_storage_service.dart';

/// Verification modes for attendance
enum VerificationMode {
  liveVerified, // Immediate sync with network (95-100)
  delayedSync, // Synced within minutes (80-90)
  offlineLocal, // Offline cached, synced later (50-70)
  manualOverride, // Supervisor manual entry (10-40)
}

/// Attendance verification service
/// Captures verification metadata for trust scoring
class AttendanceVerificationService {
  final _supabase = Supabase.instance.client;
  final _storage = SecureStorageService();

  // ============================================
  // PUNCH ATTENDANCE WITH VERIFICATION
  // ============================================

  /// Punch attendance with full verification metadata
  Future<AttendancePunchResult> punchAttendance({
    required String guardId,
    required String unitId,
    required String shift,
    bool isCheckIn = true,
    Position? gpsLocation,
    bool? faceVerified,
    double? faceMatchScore,
  }) async {
    final deviceTimestamp = DateTime.now();
    final deviceFingerprint = await _getDeviceFingerprint();

    // Prepare attendance data
    final attendanceData = {
      'guard_id': guardId,
      'unit_id': unitId,
      'shift': shift,
      'attendance_date': deviceTimestamp.toIso8601String().split('T')[0],
      'device_timestamp': deviceTimestamp.toIso8601String(),
      'device_fingerprint': deviceFingerprint,
    };

    // Add GPS location
    if (gpsLocation != null) {
      attendanceData['last_known_location'] = jsonEncode({
        'latitude': gpsLocation.latitude,
        'longitude': gpsLocation.longitude,
        'accuracy': gpsLocation.accuracy,
        'altitude': gpsLocation.altitude,
        'timestamp': deviceTimestamp.toIso8601String(),
      });
      attendanceData['gps_location'] =
          'POINT(${gpsLocation.longitude} ${gpsLocation.latitude})';
    }

    if (faceVerified != null) {
      attendanceData['face_verified'] = faceVerified.toString();
      if (faceMatchScore != null) {
        attendanceData['face_match_score'] = faceMatchScore.toString();
      }
    }

    // Add check-in or check-out time
    if (isCheckIn) {
      attendanceData['check_in_time'] = deviceTimestamp.toIso8601String();
      attendanceData['attendance_method'] = 'app';
    } else {
      attendanceData['check_out_time'] = deviceTimestamp.toIso8601String();
    }

    try {
      // Attempt live verification (network available)
      attendanceData['verification_mode'] = 'LIVE_VERIFIED';
      // server_received_timestamp will be set by database trigger

      final response = await _supabase
          .from('attendance')
          .insert(attendanceData)
          .select()
          .single()
          .timeout(const Duration(seconds: 5));

      return AttendancePunchResult(
        success: true,
        verificationMode: VerificationMode.liveVerified,
        attendanceId: response['id'] as String,
        trustScore: response['trust_score'] as int?,
        message: 'Attendance recorded successfully',
      );
    } on TimeoutException {
      // Network slow - queue as delayed sync
      return await _queueDelayedSync(attendanceData, deviceTimestamp);
    } catch (e) {
      // Network unavailable - queue offline
      return await _queueOfflineAttendance(attendanceData, deviceTimestamp);
    }
  }

  /// Queue attendance for delayed sync (slow network)
  Future<AttendancePunchResult> _queueDelayedSync(
    Map<String, dynamic> attendanceData,
    DateTime deviceTimestamp,
  ) async {
    attendanceData['verification_mode'] = 'DELAYED_SYNC';

    // Queue for background sync (retry in 30 seconds)
    final queueId = await _queueForRetry(attendanceData, retryDelay: 30);

    return AttendancePunchResult(
      success: true,
      verificationMode: VerificationMode.delayedSync,
      queueId: queueId,
      message: 'Attendance queued - syncing in background',
    );
  }

  /// Queue attendance for offline sync (no network)
  Future<AttendancePunchResult> _queueOfflineAttendance(
    Map<String, dynamic> attendanceData,
    DateTime deviceTimestamp,
  ) async {
    attendanceData['verification_mode'] = 'OFFLINE_LOCAL';

    // Use SessionStateService for offline queue
    final sessionStateService = SessionStateService();
    final queueId = await sessionStateService.queueAttendancePunch(
      attendanceData: attendanceData,
      operationType: attendanceData.containsKey('check_in_time')
          ? 'CHECK_IN'
          : 'CHECK_OUT',
      offlinePinVerified: true,
    );

    return AttendancePunchResult(
      success: true,
      verificationMode: VerificationMode.offlineLocal,
      queueId: queueId,
      message: 'Attendance saved offline - will sync when online',
    );
  }

  // ============================================
  // MANUAL OVERRIDE (Supervisor)
  // ============================================

  /// Create manual attendance entry (supervisor override)
  Future<AttendancePunchResult> createManualAttendance({
    required String guardId,
    required String unitId,
    required String shift,
    required DateTime attendanceDate,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    String? notes,
    required String supervisorId,
  }) async {
    final deviceTimestamp = DateTime.now();

    final attendanceData = {
      'guard_id': guardId,
      'unit_id': unitId,
      'shift': shift,
      'attendance_date': attendanceDate.toIso8601String().split('T')[0],
      'verification_mode': 'MANUAL_OVERRIDE',
      'attendance_method': 'manual',
      'device_timestamp': deviceTimestamp.toIso8601String(),
      'check_in_time': checkInTime?.toIso8601String(),
      'check_out_time': checkOutTime?.toIso8601String(),
      'approval_status': 'pending',
      'approval_notes': notes,
      'approved_by': supervisorId,
    };

    try {
      final response = await _supabase
          .from('attendance')
          .insert(attendanceData)
          .select()
          .single();

      return AttendancePunchResult(
        success: true,
        verificationMode: VerificationMode.manualOverride,
        attendanceId: response['id'] as String,
        trustScore: response['trust_score'] as int?,
        message: 'Manual attendance created',
      );
    } catch (e) {
      return AttendancePunchResult(
        success: false,
        verificationMode: VerificationMode.manualOverride,
        error: e.toString(),
      );
    }
  }

  // ============================================
  // SYNC OPERATIONS
  // ============================================

  /// Sync queued delayed/offline attendance
  Future<SyncResult> syncQueuedAttendance() async {
    // Get queued items from local storage
    final queueJson = await _storage.getString('attendance_retry_queue');
    if (queueJson == null) {
      return SyncResult(synced: 0, failed: 0);
    }

    final queue =
        (jsonDecode(queueJson) as List<dynamic>).cast<Map<String, dynamic>>();

    int synced = 0;
    int failed = 0;
    final newQueue = <Map<String, dynamic>>[];

    for (final item in queue) {
      try {
        final attendanceData = item['data'] as Map<String, dynamic>;
        final deviceTimestamp =
            DateTime.parse(item['device_timestamp'] as String);

        // Calculate actual sync delay
        final syncDelay = DateTime.now().difference(deviceTimestamp).inSeconds;
        attendanceData['sync_delay_seconds'] = syncDelay;

        // Update verification mode based on delay
        if (syncDelay < 300) {
          attendanceData['verification_mode'] = 'DELAYED_SYNC';
        } else {
          attendanceData['verification_mode'] = 'OFFLINE_LOCAL';
        }

        // Attempt sync
        await _supabase.from('attendance').insert(attendanceData);
        synced++;
      } catch (e) {
        // Keep in queue for retry
        newQueue.add(item);
        failed++;
      }
    }

    // Update queue
    if (newQueue.isEmpty) {
      await _storage.deleteKey('attendance_retry_queue');
    } else {
      await _storage.saveString('attendance_retry_queue', jsonEncode(newQueue));
    }

    return SyncResult(synced: synced, failed: failed);
  }

  // ============================================
  // TRUST SCORE QUERIES
  // ============================================

  /// Get attendance with verification details
  Future<List<Map<String, dynamic>>> getAttendanceWithVerification({
    String? guardId,
    String? unitId,
    DateTime? fromDate,
    DateTime? toDate,
    int? minTrustScore,
  }) async {
    var query = _supabase.from('attendance_with_verification').select();

    if (guardId != null) {
      query = query.eq('guard_id', guardId);
    }

    if (unitId != null) {
      query = query.eq('unit_id', unitId);
    }

    if (fromDate != null) {
      query = query.gte(
          'attendance_date', fromDate.toIso8601String().split('T')[0]);
    }

    if (toDate != null) {
      query =
          query.lte('attendance_date', toDate.toIso8601String().split('T')[0]);
    }

    if (minTrustScore != null) {
      query = query.gte('trust_score', minTrustScore);
    }

    return await query.order('attendance_date', ascending: false);
  }

  /// Get low trust attendance requiring review
  Future<List<Map<String, dynamic>>> getLowTrustAttendance({
    required String organizationId,
    int maxTrustScore = 60,
  }) async {
    return await _supabase
        .from('attendance_with_verification')
        .select()
        .eq('organization_id', organizationId)
        .lte('trust_score', maxTrustScore)
        .is_('approval_status', null)
        .order('trust_score', ascending: true)
        .limit(50);
  }

  /// Get trust score distribution (for reports)
  Future<Map<String, int>> getTrustScoreDistribution({
    required String organizationId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    var query = _supabase
        .from('attendance')
        .select('trust_score')
        .eq('organization_id', organizationId);

    if (fromDate != null) {
      query = query.gte(
          'attendance_date', fromDate.toIso8601String().split('T')[0]);
    }

    if (toDate != null) {
      query =
          query.lte('attendance_date', toDate.toIso8601String().split('T')[0]);
    }

    final results = await query;

    int highTrust = 0;
    int mediumTrust = 0;
    int lowTrust = 0;
    int veryLowTrust = 0;

    for (final record in results) {
      final score = record['trust_score'] as int?;
      if (score == null) continue;

      if (score >= 80) {
        highTrust++;
      } else if (score >= 60) {
        mediumTrust++;
      } else if (score >= 40) {
        lowTrust++;
      } else {
        veryLowTrust++;
      }
    }

    return {
      'HIGH_TRUST': highTrust,
      'MEDIUM_TRUST': mediumTrust,
      'LOW_TRUST': lowTrust,
      'VERY_LOW_TRUST': veryLowTrust,
    };
  }

  // ============================================
  // PRIVATE HELPERS
  // ============================================

  Future<String> _getDeviceFingerprint() async {
    return await _storage.getString('device_fingerprint') ?? 'unknown';
  }

  Future<String> _queueForRetry(Map<String, dynamic> attendanceData,
      {int retryDelay = 30}) async {
    final queueJson = await _storage.getString('attendance_retry_queue');
    final queue =
        queueJson != null ? (jsonDecode(queueJson) as List<dynamic>) : [];

    final queueId = DateTime.now().millisecondsSinceEpoch.toString();

    queue.add({
      'queue_id': queueId,
      'data': attendanceData,
      'device_timestamp': attendanceData['device_timestamp'],
      'retry_after':
          DateTime.now().add(Duration(seconds: retryDelay)).toIso8601String(),
    });

    await _storage.saveString('attendance_retry_queue', jsonEncode(queue));

    // Schedule background retry (you'll need to implement background task)
    // _scheduleBackgroundSync(retryDelay);

    return queueId;
  }
}

/// Result of attendance punch operation
class AttendancePunchResult {
  final bool success;
  final VerificationMode verificationMode;
  final String? attendanceId;
  final String? queueId;
  final int? trustScore;
  final String? message;
  final String? error;

  AttendancePunchResult({
    required this.success,
    required this.verificationMode,
    this.attendanceId,
    this.queueId,
    this.trustScore,
    this.message,
    this.error,
  });

  String get verificationLabel {
    switch (verificationMode) {
      case VerificationMode.liveVerified:
        return 'Live Verified';
      case VerificationMode.delayedSync:
        return 'Delayed Sync';
      case VerificationMode.offlineLocal:
        return 'Offline';
      case VerificationMode.manualOverride:
        return 'Manual Entry';
    }
  }

  String get trustScoreLabel {
    if (trustScore == null) return 'Pending';
    if (trustScore! >= 80) return 'High Trust';
    if (trustScore! >= 60) return 'Medium Trust';
    if (trustScore! >= 40) return 'Low Trust';
    return 'Very Low Trust';
  }
}

/// Sync result
class SyncResult {
  final int synced;
  final int failed;

  SyncResult({required this.synced, required this.failed});

  bool get hasFailures => failed > 0;
  bool get allSynced => failed == 0 && synced > 0;
}
