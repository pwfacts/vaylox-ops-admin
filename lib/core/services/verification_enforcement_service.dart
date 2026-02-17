import 'package:supabase_flutter/supabase_flutter.dart';

/// Verification task status
enum TaskStatus {
  pending,
  verified,
  justified,
  rejected,
}

/// Verification task urgency
enum TaskUrgency {
  normal,
  warning,
  critical,
}

/// Reason codes for verification tasks
enum ReasonCode {
  lowTrust,
  veryLowTrust,
  timeDrift,
  offlineExcess,
}

/// Attendance verification enforcement service
/// Manages verification tasks without blocking operations
class VerificationEnforcementService {
  final _supabase = Supabase.instance.client;

  // ============================================
  // TASK RESOLUTION
  // ============================================

  /// Resolve verification task
  Future<TaskResolutionResult> resolveTask({
    required String taskId,
    required TaskAction action,
    required String note,
  }) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) {
      throw Exception('Not authenticated');
    }

    final response = await _supabase.rpc('resolve_verification_task', params: {
      'p_task_id': taskId,
      'p_action': _actionToString(action),
      'p_note': note,
      'p_resolved_by': currentUser.id,
    });

    if (response['success'] == true) {
      return TaskResolutionResult(
        success: true,
        taskId: taskId,
        action: action,
        attendanceId: response['attendance_id'] as String?,
      );
    } else {
      return TaskResolutionResult(
        success: false,
        error: response['error'] as String?,
        message: response['message'] as String?,
      );
    }
  }

  /// Bulk resolve tasks
  Future<BulkResolutionResult> bulkResolveTasks({
    required List<String> taskIds,
    required TaskAction action,
    required String note,
  }) async {
    int succeeded = 0;
    int failed = 0;
    final errors = <String, String>{};

    for (final taskId in taskIds) {
      try {
        final result = await resolveTask(
          taskId: taskId,
          action: action,
          note: note,
        );

        if (result.success) {
          succeeded++;
        } else {
          failed++;
          errors[taskId] = result.error ?? 'Unknown error';
        }
      } catch (e) {
        failed++;
        errors[taskId] = e.toString();
      }
    }

    return BulkResolutionResult(
      succeeded: succeeded,
      failed: failed,
      errors: errors,
    );
  }

  // ============================================
  // TASK QUERIES
  // ============================================

  /// Get pending verification tasks
  Future<List<VerificationTask>> getPendingTasks({
    required String organizationId,
    String? requiredRole,
    String? reasonCode,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 50,
  }) async {
    var query = _supabase
        .from('verification_tasks_with_details')
        .select()
        .eq('organization_id', organizationId)
        .eq('status', 'PENDING');

    if (requiredRole != null) {
      query = query.eq('required_role', requiredRole);
    }

    if (reasonCode != null) {
      query = query.eq('reason_code', reasonCode);
    }

    if (fromDate != null) {
      query = query.gte(
          'attendance_date', fromDate.toIso8601String().split('T')[0]);
    }

    if (toDate != null) {
      query =
          query.lte('attendance_date', toDate.toIso8601String().split('T')[0]);
    }

    final results =
        await query.order('created_at', ascending: true).limit(limit);

    return results.map((json) => VerificationTask.fromJson(json)).toList();
  }

  /// Get verification summary for dashboard
  Future<VerificationSummary> getSummary({
    required String organizationId,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    final response =
        await _supabase.rpc('get_pending_verification_summary', params: {
      'p_org_id': organizationId,
      'p_period_start': periodStart?.toIso8601String().split('T')[0],
      'p_period_end': periodEnd?.toIso8601String().split('T')[0],
    });

    return VerificationSummary.fromJson(response);
  }

  /// Get tasks by urgency level
  Future<Map<TaskUrgency, List<VerificationTask>>> getTasksByUrgency({
    required String organizationId,
  }) async {
    final tasks = await getPendingTasks(
      organizationId: organizationId,
      limit: 100,
    );

    final byUrgency = <TaskUrgency, List<VerificationTask>>{
      TaskUrgency.critical: [],
      TaskUrgency.warning: [],
      TaskUrgency.normal: [],
    };

    for (final task in tasks) {
      byUrgency[task.urgencyLevel]!.add(task);
    }

    return byUrgency;
  }

  // ============================================
  // PAYROLL PERIOD CLOSURE
  // ============================================

  /// Check if payroll period can be closed
  Future<PeriodClosureCheck> canClosePeriod({
    required String organizationId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final response = await _supabase.rpc('can_close_payroll_period', params: {
      'p_org_id': organizationId,
      'p_period_start': periodStart.toIso8601String().split('T')[0],
      'p_period_end': periodEnd.toIso8601String().split('T')[0],
    });

    return PeriodClosureCheck.fromJson(response);
  }

  // ============================================
  // ANALYTICS
  // ============================================

  /// Get resolution statistics
  Future<ResolutionStats> getResolutionStats({
    required String organizationId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    var query = _supabase
        .from('attendance_verification_tasks')
        .select('status')
        .eq('organization_id', organizationId);

    if (fromDate != null) {
      query = query.gte('created_at', fromDate.toIso8601String());
    }

    if (toDate != null) {
      query = query.lte('created_at', toDate.toIso8601String());
    }

    final results = await query;

    int verified = 0;
    int justified = 0;
    int rejected = 0;
    int pending = 0;

    for (final record in results) {
      final status = record['status'] as String;
      switch (status) {
        case 'VERIFIED':
          verified++;
          break;
        case 'JUSTIFIED':
          justified++;
          break;
        case 'REJECTED':
          rejected++;
          break;
        case 'PENDING':
          pending++;
          break;
      }
    }

    final total = verified + justified + rejected + pending;
    final resolved = verified + justified + rejected;

    return ResolutionStats(
      verified: verified,
      justified: justified,
      rejected: rejected,
      pending: pending,
      total: total,
      resolutionRate: total > 0 ? (resolved / total * 100).round() : 0,
    );
  }

  /// Get average resolution time
  Future<Duration?> getAverageResolutionTime({
    required String organizationId,
    DateTime? fromDate,
  }) async {
    var query = _supabase
        .from('attendance_verification_tasks')
        .select('created_at, resolved_at')
        .eq('organization_id', organizationId)
        .not('resolved_at', 'is', null);

    if (fromDate != null) {
      query = query.gte('created_at', fromDate.toIso8601String());
    }

    final results = await query.limit(100);

    if (results.isEmpty) return null;

    int totalSeconds = 0;
    for (final record in results) {
      final created = DateTime.parse(record['created_at'] as String);
      final resolved = DateTime.parse(record['resolved_at'] as String);
      totalSeconds += resolved.difference(created).inSeconds;
    }

    return Duration(seconds: totalSeconds ~/ results.length);
  }

  // ============================================
  // PRIVATE HELPERS
  // ============================================

  String _actionToString(TaskAction action) {
    switch (action) {
      case TaskAction.verify:
        return 'VERIFIED';
      case TaskAction.justify:
        return 'JUSTIFIED';
      case TaskAction.reject:
        return 'REJECTED';
    }
  }
}

/// Task action enum
enum TaskAction {
  verify, // Attendance is correct
  justify, // Low trust but justified (e.g., remote location)
  reject, // Attendance is invalid
}

/// Verification task model
class VerificationTask {
  final String id;
  final String attendanceId;
  final String organizationId;
  final String requiredRole;
  final String reasonCode;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? resolutionNote;
  final int? trustScore;
  final List<String> verificationFlags;

  // Attendance details
  final DateTime attendanceDate;
  final String shift;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String verificationMode;
  final String guardName;
  final String employeeCode;
  final String unitName;

  // Computed
  final int daysPending;
  final TaskUrgency urgencyLevel;

  VerificationTask({
    required this.id,
    required this.attendanceId,
    required this.organizationId,
    required this.requiredRole,
    required this.reasonCode,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.resolvedBy,
    this.resolutionNote,
    this.trustScore,
    required this.verificationFlags,
    required this.attendanceDate,
    required this.shift,
    this.checkInTime,
    this.checkOutTime,
    required this.verificationMode,
    required this.guardName,
    required this.employeeCode,
    required this.unitName,
    required this.daysPending,
    required this.urgencyLevel,
  });

  factory VerificationTask.fromJson(Map<String, dynamic> json) {
    final urgency = json['urgency_level'] as String?;
    return VerificationTask(
      id: json['id'] as String,
      attendanceId: json['attendance_id'] as String,
      organizationId: json['organization_id'] as String,
      requiredRole: json['required_role'] as String,
      reasonCode: json['reason_code'] as String,
      status: _parseStatus(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      resolvedBy: json['resolved_by'] as String?,
      resolutionNote: json['resolution_note'] as String?,
      trustScore: json['trust_score'] as int?,
      verificationFlags:
          (json['verification_flags'] as List<dynamic>?)?.cast<String>() ?? [],
      attendanceDate: DateTime.parse(json['attendance_date'] as String),
      shift: json['shift'] as String,
      checkInTime: json['check_in_time'] != null
          ? DateTime.parse(json['check_in_time'] as String)
          : null,
      checkOutTime: json['check_out_time'] != null
          ? DateTime.parse(json['check_out_time'] as String)
          : null,
      verificationMode: json['verification_mode'] as String,
      guardName: json['guard_name'] as String,
      employeeCode: json['employee_code'] as String,
      unitName: json['unit_name'] as String,
      daysPending: json['days_pending'] as int,
      urgencyLevel: urgency == 'CRITICAL'
          ? TaskUrgency.critical
          : urgency == 'WARNING'
              ? TaskUrgency.warning
              : TaskUrgency.normal,
    );
  }

  static TaskStatus _parseStatus(String status) {
    switch (status) {
      case 'PENDING':
        return TaskStatus.pending;
      case 'VERIFIED':
        return TaskStatus.verified;
      case 'JUSTIFIED':
        return TaskStatus.justified;
      case 'REJECTED':
        return TaskStatus.rejected;
      default:
        return TaskStatus.pending;
    }
  }
}

/// Verification summary for dashboard
class VerificationSummary {
  final int pendingReviews;
  final int criticalUnverified;
  final int agingTasks;
  final Map<String, int> byReason;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  VerificationSummary({
    required this.pendingReviews,
    required this.criticalUnverified,
    required this.agingTasks,
    required this.byReason,
    this.periodStart,
    this.periodEnd,
  });

  factory VerificationSummary.fromJson(Map<String, dynamic> json) {
    return VerificationSummary(
      pendingReviews: json['pending_reviews'] as int,
      criticalUnverified: json['critical_unverified'] as int,
      agingTasks: json['aging_tasks'] as int,
      byReason: (json['by_reason'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
      periodStart: json['period_start'] != null
          ? DateTime.parse(json['period_start'] as String)
          : null,
      periodEnd: json['period_end'] != null
          ? DateTime.parse(json['period_end'] as String)
          : null,
    );
  }
}

/// Period closure check result
class PeriodClosureCheck {
  final bool canClose;
  final int unresolvedCount;
  final int criticalCount;
  final List<Map<String, dynamic>> unresolvedTasks;
  final String message;

  PeriodClosureCheck({
    required this.canClose,
    required this.unresolvedCount,
    required this.criticalCount,
    required this.unresolvedTasks,
    required this.message,
  });

  factory PeriodClosureCheck.fromJson(Map<String, dynamic> json) {
    return PeriodClosureCheck(
      canClose: json['can_close'] as bool,
      unresolvedCount: json['unresolved_count'] as int,
      criticalCount: json['critical_count'] as int,
      unresolvedTasks: (json['unresolved_tasks'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [],
      message: json['message'] as String,
    );
  }
}

/// Task resolution result
class TaskResolutionResult {
  final bool success;
  final String? taskId;
  final TaskAction? action;
  final String? attendanceId;
  final String? error;
  final String? message;

  TaskResolutionResult({
    required this.success,
    this.taskId,
    this.action,
    this.attendanceId,
    this.error,
    this.message,
  });
}

/// Bulk resolution result
class BulkResolutionResult {
  final int succeeded;
  final int failed;
  final Map<String, String> errors;

  BulkResolutionResult({
    required this.succeeded,
    required this.failed,
    required this.errors,
  });

  bool get allSucceeded => failed == 0;
  int get total => succeeded + failed;
}

/// Resolution statistics
class ResolutionStats {
  final int verified;
  final int justified;
  final int rejected;
  final int pending;
  final int total;
  final int resolutionRate; // Percentage

  ResolutionStats({
    required this.verified,
    required this.justified,
    required this.rejected,
    required this.pending,
    required this.total,
    required this.resolutionRate,
  });
}
