import '../services/supabase_service.dart';
import '../models/salary_slip_model.dart';

class AuditLogEntry {
  final String id;
  final String actorName;
  final DateTime timestamp;
  final String action;
  final String details;
  final String type; // 'SALARY' or 'ATTENDANCE'

  AuditLogEntry({
    required this.id,
    required this.actorName,
    required this.timestamp,
    required this.action,
    required this.details,
    required this.type,
  });
}

class AuditRepository {
  final _client = SupabaseService().client;

  Future<List<AuditLogEntry>> getRecentAudits() async {
    final List<AuditLogEntry> logs = [];

    // 1. Fetch Salary Overrides (from salary_slips where manual_override_by is not null)
    final salaryRes = await _client
        .from('salary_slips')
        .select('*, guards(full_name)')
        .not('manual_override_by', 'is', null)
        .order('manual_override_at', ascending: false)
        .limit(20);

    for (var row in (salaryRes as List)) {
      logs.add(AuditLogEntry(
        id: row['id'],
        actorName: row['manual_override_by'],
        timestamp: DateTime.parse(row['manual_override_at']),
        action: 'Salary Override',
        details: 'Override for ${row['guards']['full_name']}: ${row['manual_override_note'] ?? 'No reason provided'}',
        type: 'SALARY',
      ));
    }

    // 2. Fetch Attendance Approvals (from attendance_audit_log if it exists, otherwise from attendance table)
    // For now, let's fetch from attendance table where approved_by is not null
    final attendanceRes = await _client
        .from('attendance')
        .select('*, guards(full_name)')
        .not('approved_by', 'is', null)
        .order('approved_at', ascending: false)
        .limit(20);

    for (var row in (attendanceRes as List)) {
      logs.add(AuditLogEntry(
        id: row['id'],
        actorName: 'Supervisor', // We'd ideally join with a users table
        timestamp: DateTime.parse(row['approved_at']),
        action: row['approval_status'] == 'APPROVED' ? 'Attendance Approved' : 'Attendance Rejected',
        details: '${row['approval_status']} for ${row['guards']['full_name']} on ${row['attendance_date']}',
        type: 'ATTENDANCE',
      ));
    }

    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return logs;
  }
}
