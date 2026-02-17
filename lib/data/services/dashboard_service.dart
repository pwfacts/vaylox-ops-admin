import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/scoped_query_helper.dart';

class DashboardService {
  final ScopedQueryHelper _scopedHelper =
      ScopedQueryHelper(); // Should use DI/Provider really

  Future<Map<String, dynamic>> getOperationalMetrics() async {
    // 1. Total Active Guards (Scoped)
    // For admin, it's all. For FO, it's their units.
    var guardsQuery = await _scopedHelper.scopedQuery('guards', select: 'id');
    final guardsResponse =
        await guardsQuery.eq('status', 'active').count(CountOption.exact);
    final guardsCount = guardsResponse.count;

    // 2. Units Count (Scoped)
    var unitsQuery = await _scopedHelper.scopedQuery('units', select: 'id');
    final unitsResponse =
        await unitsQuery.eq('status', 'active').count(CountOption.exact);
    final unitsCount = unitsResponse.count;

    // 3. Attendance Today
    final today = DateTime.now().toIso8601String().split('T')[0];

    var attendanceQuery = await _scopedHelper.scopedQuery('attendance',
        select: 'approval_status, check_in_time');
    final attendanceData = await attendanceQuery.eq('attendance_date', today);

    final List<dynamic> records = attendanceData as List<dynamic>;

    final presentCount =
        records.where((r) => r['check_in_time'] != null).length;
    final pendingCount =
        records.where((r) => r['approval_status'] == 'PENDING_APPROVAL').length;

    // Missing = Total Guards - Present (Rough approximation)
    final missingCount = (guardsCount - presentCount);

    return {
      'total_guards': guardsCount,
      'total_units': unitsCount,
      'present_today': presentCount,
      'pending_approvals': pendingCount,
      'missing_today': missingCount > 0 ? missingCount : 0,
    };
  }

  Future<List<Map<String, dynamic>>> getRecentActivity() async {
    // Audit logs for recent actions
    // Or just recent attendance events?
    // Let's perform a join manually or use audit logs if populated.
    // For now, let's fetch recent attendance check-ins.

    var query = await _scopedHelper.scopedQuery('attendance',
        select: '*, guards(full_name, unit_id), units(name)');

    final data = await query.order('created_at', ascending: false).limit(10);

    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Map<String, dynamic>>> getMyUnits() async {
    // For Field Officers/Supervisors, get their specific units
    // For Admin, get all active units
    // ScopedQueryHelper 'units' query handles the filtering automatically!

    var query = await _scopedHelper.scopedQuery('units');
    final data = await query.eq('status', 'active').order('name');

    return List<Map<String, dynamic>>.from(data as List);
  }
}
