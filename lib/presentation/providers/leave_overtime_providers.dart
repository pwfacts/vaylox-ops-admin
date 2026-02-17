import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/delta_sync_service.dart';
import '../../data/services/supabase_service.dart';
import 'package:logger/logger.dart';

/// ============================================
/// LEAVE REQUESTS PROVIDER (Delta Sync)
/// ============================================

class LeaveRequest {
  final String id;
  final String organizationId;
  final String guardId;
  final String unitId;
  final DateTime leaveDate;
  final String leaveType;
  final String reason;
  final String status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final String? attendanceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  LeaveRequest({
    required this.id,
    required this.organizationId,
    required this.guardId,
    required this.unitId,
    required this.leaveDate,
    required this.leaveType,
    required this.reason,
    required this.status,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
    this.attendanceId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    return LeaveRequest(
      id: json['id'] as String,
      organizationId: json['organization_id'] as String,
      guardId: json['guard_id'] as String,
      unitId: json['unit_id'] as String,
      leaveDate: DateTime.parse(json['leave_date'] as String),
      leaveType: json['leave_type'] as String,
      reason: json['reason'] as String,
      status: json['status'] as String,
      reviewedBy: json['reviewed_by'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      rejectionReason: json['rejection_reason'] as String?,
      attendanceId: json['attendance_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class LeaveRequestsNotifier
    extends StateNotifier<AsyncValue<List<LeaveRequest>>> {
  final DeltaSyncService _syncService;
  final String? guardId; // For guard's own requests
  final String? unitId; // For field officer's unit
  final String? organizationId; // For admin
  Timer? _pollTimer;
  List<LeaveRequest> _cache = [];
  final _logger = Logger();

  LeaveRequestsNotifier(
    this._syncService, {
    this.guardId,
    this.unitId,
    this.organizationId,
  }) : super(const AsyncValue.loading()) {
    _initialize();
  }

  Future<void> _initialize() async {
    await _fullSync();
    _pollTimer = Timer.periodic(
      DeltaSyncService.leaveRequestsPollInterval,
      (_) => _deltaSync(),
    );
  }

  Future<void> _fullSync() async {
    try {
      var query = SupabaseService.client.from('leave_requests').select();

      // Apply filters based on role
      if (guardId != null) {
        query = query.eq('guard_id', guardId!);
      } else if (unitId != null) {
        query = query.eq('unit_id', unitId!);
      } else if (organizationId != null) {
        query = query.eq('organization_id', organizationId!);
      }

      final response = await query.order('created_at', ascending: false);

      _cache = (response as List)
          .map((json) => LeaveRequest.fromJson(json as Map<String, dynamic>))
          .toList();

      state = AsyncValue.data(_cache);

      await _syncService.updateLastSync('leave_requests', DateTime.now());
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> _deltaSync() async {
    try {
      Map<String, dynamic>? filters;

      if (guardId != null) {
        filters = {'guard_id': guardId};
      } else if (unitId != null) {
        filters = {'unit_id': unitId};
      }

      final delta = await _syncService.fetchDelta(
        tableName: 'leave_requests',
        organizationFilter: organizationId,
        additionalFilters: filters,
      );

      if (delta.isNotEmpty) {
        _cache = await _syncService.fetchDeltaWithCache<LeaveRequest>(
          tableName: 'leave_requests',
          currentCache: _cache,
          fromJson: (json) => LeaveRequest.fromJson(json),
          getId: (item) => item.id,
          organizationFilter: organizationId,
          additionalFilters: filters,
        );

        state = AsyncValue.data(_cache);
      }
    } catch (e) {
      _logger.w('Delta sync error for leave requests: $e');
    }
  }

  /// Create new leave request
  Future<void> createLeaveRequest({
    required String guardId,
    required String unitId,
    required String organizationId,
    required DateTime leaveDate,
    required String leaveType,
    required String reason,
  }) async {
    try {
      await SupabaseService.client.from('leave_requests').insert({
        'guard_id': guardId,
        'unit_id': unitId,
        'organization_id': organizationId,
        'leave_date': leaveDate.toIso8601String().split('T')[0],
        'leave_type': leaveType,
        'reason': reason,
        'status': 'PENDING',
      });

      // Force refresh
      await _fullSync();
    } catch (e) {
      _logger.e('Error creating leave request:', error: e);
      rethrow;
    }
  }

  /// Approve leave request (field officer/admin)
  Future<void> approveLeaveRequest(
    String leaveRequestId,
    String reviewedBy,
  ) async {
    try {
      final leaveRequest = _cache.firstWhere((lr) => lr.id == leaveRequestId);

      // Update leave request status
      await SupabaseService.client.from('leave_requests').update({
        'status': 'APPROVED',
        'reviewed_by': reviewedBy,
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', leaveRequestId);

      // Create attendance record for leave
      final attendanceResponse = await SupabaseService.client
          .from('attendance')
          .insert({
            'organization_id': leaveRequest.organizationId,
            'guard_id': leaveRequest.guardId,
            'unit_id': leaveRequest.unitId,
            'attendance_date':
                leaveRequest.leaveDate.toIso8601String().split('T')[0],
            'shift': 'day', // Default
            'type': 'NORMAL',
            'attendance_method': 'SUPERVISOR',
            'approval_status': 'APPROVED',
            'approved_by': reviewedBy,
            'approved_at': DateTime.now().toIso8601String(),
            'marked_by_user_id': reviewedBy,
            // Mark as present but with leave flag in notes
            'approval_notes': 'Approved Leave - ${leaveRequest.leaveType}',
          })
          .select()
          .single();

      // Link attendance to leave request
      await SupabaseService.client.from('leave_requests').update({
        'attendance_id': attendanceResponse['id'],
      }).eq('id', leaveRequestId);

      // Trigger unit stats recalculation (handled by trigger)

      await _fullSync();
    } catch (e) {
      _logger.e('Error approving leave request:', error: e);
      rethrow;
    }
  }

  /// Reject leave request
  Future<void> rejectLeaveRequest(
    String leaveRequestId,
    String reviewedBy,
    String? rejectionReason,
  ) async {
    try {
      await SupabaseService.client.from('leave_requests').update({
        'status': 'REJECTED',
        'reviewed_by': reviewedBy,
        'reviewed_at': DateTime.now().toIso8601String(),
        'rejection_reason': rejectionReason,
      }).eq('id', leaveRequestId);

      await _fullSync();
    } catch (e) {
      _logger.e('Error rejecting leave request:', error: e);
      rethrow;
    }
  }

  /// Cancel own leave request (guard)
  Future<void> cancelLeaveRequest(String leaveRequestId) async {
    try {
      await SupabaseService.client
          .from('leave_requests')
          .update({
            'status': 'CANCELLED',
          })
          .eq('id', leaveRequestId)
          .eq('status', 'PENDING');

      await _fullSync();
    } catch (e) {
      _logger.e('Error cancelling leave request:', error: e);
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _fullSync();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

/// Provider for guard's own leave requests
final myLeaveRequestsProvider = StateNotifierProvider.family<
    LeaveRequestsNotifier, AsyncValue<List<LeaveRequest>>, String>(
  (ref, guardId) {
    final syncService = ref.watch(deltaSyncServiceProvider);
    return LeaveRequestsNotifier(syncService, guardId: guardId);
  },
);

/// Provider for field officer's unit leave requests
final unitLeaveRequestsProvider = StateNotifierProvider.family<
    LeaveRequestsNotifier, AsyncValue<List<LeaveRequest>>, String>(
  (ref, unitId) {
    final syncService = ref.watch(deltaSyncServiceProvider);
    return LeaveRequestsNotifier(syncService, unitId: unitId);
  },
);

/// Provider for admin's organization leave requests
final orgLeaveRequestsProvider = StateNotifierProvider.family<
    LeaveRequestsNotifier, AsyncValue<List<LeaveRequest>>, String>(
  (ref, organizationId) {
    final syncService = ref.watch(deltaSyncServiceProvider);
    return LeaveRequestsNotifier(syncService, organizationId: organizationId);
  },
);

/// Pending leave requests count
final pendingLeaveCountProvider = Provider.family<int, String>((ref, filter) {
  // Filter can be guardId, unitId, or organizationId
  // Determine which provider to use based on context
  final leaves = ref.watch(orgLeaveRequestsProvider(filter));

  return leaves.when(
    data: (list) => list.where((lr) => lr.status == 'PENDING').length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});

/// ============================================
/// OVERTIME REQUESTS PROVIDER (Delta Sync)
/// ============================================

class OvertimeRequest {
  final String id;
  final String organizationId;
  final String guardId;
  final String unitId;
  final DateTime overtimeDate;
  final double requestedHours;
  final String? shift;
  final String? reason;
  final String status;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectionReason;
  final String? attendanceId;
  final double? otRateApplied;
  final DateTime createdAt;
  final DateTime updatedAt;

  OvertimeRequest({
    required this.id,
    required this.organizationId,
    required this.guardId,
    required this.unitId,
    required this.overtimeDate,
    required this.requestedHours,
    this.shift,
    this.reason,
    required this.status,
    this.approvedBy,
    this.approvedAt,
    this.rejectionReason,
    this.attendanceId,
    this.otRateApplied,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OvertimeRequest.fromJson(Map<String, dynamic> json) {
    return OvertimeRequest(
      id: json['id'] as String,
      organizationId: json['organization_id'] as String,
      guardId: json['guard_id'] as String,
      unitId: json['unit_id'] as String,
      overtimeDate: DateTime.parse(json['overtime_date'] as String),
      requestedHours: (json['requested_hours'] as num).toDouble(),
      shift: json['shift'] as String?,
      reason: json['reason'] as String?,
      status: json['status'] as String,
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      rejectionReason: json['rejection_reason'] as String?,
      attendanceId: json['attendance_id'] as String?,
      otRateApplied: json['ot_rate_applied'] != null
          ? (json['ot_rate_applied'] as num).toDouble()
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class OvertimeRequestsNotifier
    extends StateNotifier<AsyncValue<List<OvertimeRequest>>> {
  final DeltaSyncService _syncService;
  final String? guardId;
  final String? unitId;
  final String? organizationId;
  Timer? _pollTimer;
  List<OvertimeRequest> _cache = [];
  final _logger = Logger();

  OvertimeRequestsNotifier(
    this._syncService, {
    this.guardId,
    this.unitId,
    this.organizationId,
  }) : super(const AsyncValue.loading()) {
    _initialize();
  }

  Future<void> _initialize() async {
    await _fullSync();
    _pollTimer = Timer.periodic(
      DeltaSyncService.overtimeRequestsPollInterval,
      (_) => _deltaSync(),
    );
  }

  Future<void> _fullSync() async {
    try {
      var query = SupabaseService.client.from('overtime_requests').select();

      if (guardId != null) {
        query = query.eq('guard_id', guardId!);
      } else if (unitId != null) {
        query = query.eq('unit_id', unitId!);
      } else if (organizationId != null) {
        query = query.eq('organization_id', organizationId!);
      }

      final response = await query.order('created_at', ascending: false);

      _cache = (response as List)
          .map((json) => OvertimeRequest.fromJson(json as Map<String, dynamic>))
          .toList();

      state = AsyncValue.data(_cache);

      await _syncService.updateLastSync('overtime_requests', DateTime.now());
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> _deltaSync() async {
    try {
      Map<String, dynamic>? filters;

      if (guardId != null) {
        filters = {'guard_id': guardId};
      } else if (unitId != null) {
        filters = {'unit_id': unitId};
      }

      _cache = await _syncService.fetchDeltaWithCache<OvertimeRequest>(
        tableName: 'overtime_requests',
        currentCache: _cache,
        fromJson: (json) => OvertimeRequest.fromJson(json),
        getId: (item) => item.id,
        organizationFilter: organizationId,
        additionalFilters: filters,
      );

      state = AsyncValue.data(_cache);
    } catch (e) {
      _logger.w('Delta sync error for OT requests: $e');
    }
  }

  /// Create OT request
  Future<void> createOTRequest({
    required String guardId,
    required String unitId,
    required String organizationId,
    required DateTime overtimeDate,
    required double requestedHours,
    required String shift,
    String? reason,
  }) async {
    try {
      await SupabaseService.client.from('overtime_requests').insert({
        'guard_id': guardId,
        'unit_id': unitId,
        'organization_id': organizationId,
        'overtime_date': overtimeDate.toIso8601String().split('T')[0],
        'requested_hours': requestedHours,
        'shift': shift,
        'reason': reason,
        'status': 'PENDING',
      });

      await _fullSync();
    } catch (e) {
      _logger.e('Error creating OT request:', error: e);
      rethrow;
    }
  }

  /// Approve OT request and create attendance
  Future<void> approveOTRequest(
    String otRequestId,
    String approvedBy,
    double otRate,
  ) async {
    try {
      final otRequest = _cache.firstWhere((ot) => ot.id == otRequestId);

      // Create OT attendance record
      final attendanceResponse = await SupabaseService.client
          .from('attendance')
          .insert({
            'organization_id': otRequest.organizationId,
            'guard_id': otRequest.guardId,
            'unit_id': otRequest.unitId,
            'attendance_date':
                otRequest.overtimeDate.toIso8601String().split('T')[0],
            'shift': otRequest.shift ?? 'day',
            'type': 'OT',
            'is_ot': true,
            'ot_hours': otRequest.requestedHours,
            'ot_rate_applied': otRate,
            'attendance_method': 'SUPERVISOR',
            'approval_status': 'APPROVED',
            'approved_by': approvedBy,
            'approved_at': DateTime.now().toIso8601String(),
            'marked_by_user_id': approvedBy,
          })
          .select()
          .single();

      // Update OT request
      await SupabaseService.client.from('overtime_requests').update({
        'status': 'APPROVED',
        'approved_by': approvedBy,
        'approved_at': DateTime.now().toIso8601String(),
        'ot_rate_applied': otRate,
        'attendance_id': attendanceResponse['id'],
      }).eq('id', otRequestId);

      await _fullSync();
    } catch (e) {
      _logger.e('Error approving OT request:', error: e);
      rethrow;
    }
  }

  /// Reject OT request
  Future<void> rejectOTRequest(
    String otRequestId,
    String approvedBy,
    String? rejectionReason,
  ) async {
    try {
      await SupabaseService.client.from('overtime_requests').update({
        'status': 'REJECTED',
        'approved_by': approvedBy,
        'approved_at': DateTime.now().toIso8601String(),
        'rejection_reason': rejectionReason,
      }).eq('id', otRequestId);

      await _fullSync();
    } catch (e) {
      _logger.e('Error rejecting OT request:', error: e);
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _fullSync();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

/// Provider for guard's own OT requests
final myOTRequestsProvider = StateNotifierProvider.family<
    OvertimeRequestsNotifier, AsyncValue<List<OvertimeRequest>>, String>(
  (ref, guardId) {
    final syncService = ref.watch(deltaSyncServiceProvider);
    return OvertimeRequestsNotifier(syncService, guardId: guardId);
  },
);

/// Provider for field officer's unit OT requests
final unitOTRequestsProvider = StateNotifierProvider.family<
    OvertimeRequestsNotifier, AsyncValue<List<OvertimeRequest>>, String>(
  (ref, unitId) {
    final syncService = ref.watch(deltaSyncServiceProvider);
    return OvertimeRequestsNotifier(syncService, unitId: unitId);
  },
);

/// Provider for admin's organization OT requests
final orgOTRequestsProvider = StateNotifierProvider.family<
    OvertimeRequestsNotifier, AsyncValue<List<OvertimeRequest>>, String>(
  (ref, organizationId) {
    final syncService = ref.watch(deltaSyncServiceProvider);
    return OvertimeRequestsNotifier(syncService,
        organizationId: organizationId);
  },
);
