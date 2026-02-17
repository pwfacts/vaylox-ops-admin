import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/attendance_model.dart';
import '../models/attendance_correction_model.dart';
import '../services/supabase_service.dart';
import '../services/local_database_service.dart';
import '../../core/utils/scoped_query_helper.dart';
import 'package:logger/logger.dart';

/// Production-grade attendance repository with strict sync and approval workflows
class AttendanceRepository {
  final SupabaseClient _client = SupabaseService.client;
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final _logger = Logger();

  /// Mark attendance with duplicate detection and multi-unit support
  Future<Map<String, dynamic>> markAttendance({
    required Attendance attendance,
    required String primaryUnitId,
    required String workedUnitId,
    bool isOffline = false,
  }) async {
    try {
      // 1. Check for duplicates if syncing from offline
      if (attendance.syncedFromOffline && attendance.deviceId != null) {
        final duplicateCheck = await _client.rpc(
          'check_attendance_duplicate',
          params: {
            'p_guard_id': attendance.guardId,
            'p_attendance_date':
                attendance.attendanceDate.toIso8601String().split('T')[0],
            'p_shift': attendance.shift,
            'p_device_id': attendance.deviceId!,
            'p_offline_created_at':
                attendance.offlineCreatedAt?.toIso8601String(),
          },
        );

        if (duplicateCheck != null && duplicateCheck.isNotEmpty) {
          final result = duplicateCheck[0] as Map<String, dynamic>;
          if (result['is_duplicate'] == true) {
            // Register in sync registry
            await _client.from('attendance_sync_registry').insert({
              'device_id': attendance.deviceId,
              'guard_id': attendance.guardId,
              'attendance_date':
                  attendance.attendanceDate.toIso8601String().split('T')[0],
              'shift': attendance.shift,
              'offline_created_at':
                  attendance.offlineCreatedAt?.toIso8601String(),
              'synced_attendance_id': result['existing_attendance_id'],
              'sync_status': 'DUPLICATE_DETECTED',
              'conflict_resolution_method': result['conflict_type'],
            });

            return {
              'success': false,
              'isDuplicate': true,
              'existingId': result['existing_attendance_id'],
              'conflictType': result['conflict_type'],
            };
          }
        }
      }

      // 2. Prepare attendance data with multi-unit fields
      final attendanceData = attendance.toJson();
      attendanceData['primary_unit_id'] = primaryUnitId;
      attendanceData['worked_unit_id'] = workedUnitId;
      attendanceData['approval_status'] = 'PENDING_APPROVAL';

      // Remove check_in_method if it doesn't exist in your model
      // The migration added this column, ensure model handles it
      if (!attendanceData.containsKey('check_in_method')) {
        attendanceData['check_in_method'] =
            attendance.attendanceMethod.name.toUpperCase();
      }

      // 3. Insert attendance
      if (isOffline) {
        await _localDb.insertAttendance(attendanceData);
        return {'success': true, 'id': attendance.id, 'offline': true};
      } else {
        final response = await _client
            .from('attendance')
            .insert(attendanceData)
            .select()
            .single();

        // 4. Register successful sync if from offline
        if (attendance.syncedFromOffline && attendance.deviceId != null) {
          await _client.from('attendance_sync_registry').insert({
            'device_id': attendance.deviceId,
            'guard_id': attendance.guardId,
            'attendance_date':
                attendance.attendanceDate.toIso8601String().split('T')[0],
            'shift': attendance.shift,
            'offline_created_at':
                attendance.offlineCreatedAt?.toIso8601String(),
            'synced_attendance_id': response['id'],
            'sync_status': 'SYNCED',
          });
        }

        return {'success': true, 'id': response['id'], 'data': response};
      }
    } catch (e) {
      _logger.e('Failed to mark attendance: $e');
      throw Exception('Failed to mark attendance: $e');
    }
  }

  /// Get today's attendance for a guard (checking for duplicates)
  Future<Attendance?> getTodayAttendance(String guardId, String shift) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final response = await _client
        .from('attendance')
        .select()
        .eq('guard_id', guardId)
        .eq('attendance_date', today)
        .eq('shift', shift)
        .eq('is_voided', false)
        .maybeSingle();

    if (response == null) return null;
    return Attendance.fromJson(response);
  }

  /// Get pending approvals for a supervisor/field officer
  Future<List<Attendance>> getPendingApprovals(String unitId) async {
    final response = await _client
        .from('attendance')
        .select('*, guards(full_name, guard_code)')
        .eq('worked_unit_id', unitId) // Check worked_unit, not unit_id
        .eq('approval_status', 'PENDING_APPROVAL')
        .eq('is_voided', false)
        .order('created_at', ascending: false);

    return (response as List).map((json) => Attendance.fromJson(json)).toList();
  }

  /// Approve or reject attendance (supervisors/field officers only for their units)
  Future<void> updateAttendanceStatus({
    required String attendanceId,
    required String status,
    required String approverId,
    String? notes,
  }) async {
    await _client.from('attendance').update({
      'approval_status': status,
      'approved_by': approverId,
      'approved_at': DateTime.now().toIso8601String(),
      'approval_notes': notes,
    }).eq('id', attendanceId);
  }

  /// Void attendance (admin only, creates log entry via trigger)
  Future<void> voidAttendance({
    required String attendanceId,
    required String voidedBy,
    required String reason,
  }) async {
    await _client.from('attendance').update({
      'is_voided': true,
      'voided_by': voidedBy,
      'voided_at': DateTime.now().toIso8601String(),
      'void_reason': reason,
    }).eq('id', attendanceId);
  }

  /// Get attendance logs with scoped access
  Future<List<Map<String, dynamic>>> getAttendanceLogs({
    String? date,
    String? unitId,
    String? status,
  }) async {
    final scopedHelper = ScopedQueryHelper();
    var query = await scopedHelper.scopedQuery(
      'attendance',
      select:
          '*, guards(full_name, guard_code), units!attendance_worked_unit_id_fkey(name)',
    );

    // Filter by date
    if (date != null) {
      query = query.eq('attendance_date', date);
    }

    // Filter by worked unit (for multi-unit assignments)
    if (unitId != null) {
      query = query.eq('worked_unit_id', unitId);
    }

    // Filter by approval status
    if (status != null && status != 'all') {
      query = query.eq('approval_status', status);
    }

    // Exclude voided records
    query = query.eq('is_voided', false);

    final response = await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response as List);
  }

  /// Get attendance report (scoped to user's access)
  Future<List<Map<String, dynamic>>> getAttendanceReport({
    required DateTime startDate,
    required DateTime endDate,
    String? unitId,
  }) async {
    final scopedHelper = ScopedQueryHelper();
    var query = await scopedHelper.scopedQuery(
      'attendance',
      select:
          '*, guards(full_name, guard_code), units!attendance_worked_unit_id_fkey(name)',
    );

    query = query
        .gte('attendance_date', startDate.toIso8601String().split('T')[0])
        .lte('attendance_date', endDate.toIso8601String().split('T')[0])
        .eq('is_voided', false);

    if (unitId != null) {
      query = query.eq('worked_unit_id', unitId);
    }

    final response = await query.order('attendance_date', ascending: true);
    return List<Map<String, dynamic>>.from(response as List);
  }

  /// Get payroll-ready attendance using database function
  Future<List<Map<String, dynamic>>> getPayrollAttendance({
    required String organizationId,
    required DateTime startDate,
    required DateTime endDate,
    String? unitId,
  }) async {
    final response = await _client.rpc(
      'get_payroll_attendance',
      params: {
        'p_organization_id': organizationId,
        'p_start_date': startDate.toIso8601String().split('T')[0],
        'p_end_date': endDate.toIso8601String().split('T')[0],
        'p_unit_id': unitId,
      },
    );

    return List<Map<String, dynamic>>.from(response as List);
  }

  /// Get attendance statistics
  Future<Map<String, dynamic>> getAttendanceStats() async {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    final today = now.toIso8601String().split('T')[0];

    final scopedHelper = ScopedQueryHelper();

    final totalQuery = await scopedHelper.scopedQuery('attendance',
        select: 'id, check_in_method, approval_status');
    final totalResponse = await totalQuery
        .gte('attendance_date', firstDayOfMonth.toIso8601String().split('T')[0])
        .lte('attendance_date', today)
        .eq('is_voided', false);

    final total = totalResponse.length;
    final manual = totalResponse
        .where((r) =>
            r['check_in_method'] == 'MANUAL' ||
            r['check_in_method'] == 'MANUALFALLBACK')
        .length;
    final pending = totalResponse
        .where((r) => r['approval_status'] == 'PENDING_APPROVAL')
        .length;
    final rejected =
        totalResponse.where((r) => r['approval_status'] == 'REJECTED').length;

    return {
      'total': total,
      'manual': manual,
      'pending': pending,
      'rejected': rejected,
    };
  }

  // ============================================================================
  // CORRECTION WORKFLOW
  // ============================================================================

  /// Request a correction for approved attendance
  Future<void> requestCorrection({
    required String attendanceId,
    required String organizationId,
    required CorrectionType type,
    required String reason,
    required String requestedBy,
    String? fieldChanged,
    String? oldValue,
    String? newValue,
  }) async {
    await _client.from('attendance_corrections').insert({
      'id': const Uuid().v4(),
      'organization_id': organizationId,
      'attendance_id': attendanceId,
      'correction_type': type.name.toUpperCase().replaceAll(
            RegExp(r'([a-z])([A-Z])'),
            r'$1_$2',
          ),
      'field_changed': fieldChanged,
      'old_value': oldValue,
      'new_value': newValue,
      'reason': reason,
      'requested_by': requestedBy,
    });
  }

  /// Get all correction requests
  Future<List<AttendanceCorrection>> getCorrections({
    String? status,
  }) async {
    var query = _client.from('attendance_corrections').select();

    if (status != null) {
      query = query.eq('correction_status', status.toUpperCase());
    }

    final response = await query.order('requested_at', ascending: false);
    return (response as List)
        .map((json) => AttendanceCorrection.fromJson(json))
        .toList();
  }

  /// Approve or reject a correction request (admin only)
  Future<void> processCorrectionRequest({
    required String correctionId,
    required bool approve,
    required String approvedBy,
    String? rejectionReason,
  }) async {
    await _client.from('attendance_corrections').update({
      'correction_status': approve ? 'APPROVED' : 'REJECTED',
      'approved_by': approvedBy,
      'approved_at': DateTime.now().toIso8601String(),
      'rejection_reason': rejectionReason,
    }).eq('id', correctionId);
  }

  /// Get approval log for an attendance record
  Future<List<Map<String, dynamic>>> getApprovalLog(String attendanceId) async {
    final response = await _client
        .from('attendance_approval_log')
        .select('*, users(full_name, email)')
        .eq('attendance_id', attendanceId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response as List);
  }
}
