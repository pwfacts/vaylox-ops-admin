import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/attendance_model.dart';
import '../services/supabase_service.dart';
import '../services/local_database_service.dart';

class AttendanceRepository {
  final SupabaseClient _client = SupabaseService().client;
  final LocalDatabaseService _localDb = LocalDatabaseService();

  Future<void> markAttendance({
    required Attendance attendance,
    bool isOffline = false,
  }) async {
    try {
      if (isOffline) {
        // Save to local SQLite queue
        await _localDb.insertAttendance(attendance.toJson());
      } else {
        // Insert directly to Supabase
        await _client.from('attendance').insert(attendance.toJson());
      }
    } catch (e) {
      throw Exception('Failed to mark attendance: $e');
    }
  }

  Future<Attendance?> getTodayAttendance(String guardId, String shift) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final response = await _client
        .from('attendance')
        .select()
        .eq('guard_id', guardId)
        .eq('attendance_date', today)
        .eq('shift', shift)
        .maybeSingle();

    if (response == null) return null;
    return Attendance.fromJson(response);
  }

  Future<List<Attendance>> getPendingApprovals(String unitId) async {
    final response = await _client
        .from('attendance')
        .select('*, guards(full_name, guard_code)')
        .eq('unit_id', unitId)
        .eq('approval_status', 'PENDING_APPROVAL')
        .order('created_at', ascending: false);

    return (response as List).map((json) => Attendance.fromJson(json)).toList();
  }

  Future<void> approveAttendance(String id, String approvedBy, String? notes) async {
    await _client.from('attendance').update({
      'approval_status': 'APPROVED',
      'approved_by': approvedBy,
      'approved_at': DateTime.now().toIso8601String(),
      'approval_notes': notes,
    }).eq('id', id);
  }
}
