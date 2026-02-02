import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/services/supabase_service.dart';
import '../../data/models/unit_model.dart';
import '../../data/models/guard_model.dart';
import './guard_enrollment_provider.dart';

final attendanceRepositoryProvider = Provider((ref) => AttendanceRepository());

final unitsProvider = FutureProvider<List<Unit>>((ref) async {
  final client = SupabaseService().client;
  final response = await client.from('units').select().order('name');
  return (response as List).map((json) => Unit.fromJson(json)).toList();
});

final unitAttendanceSummaryProvider =
    FutureProvider.family<Map<String, Map<String, int>>, Map<String, dynamic>>((
      ref,
      params,
    ) async {
      final client = SupabaseService().client;
      final unitId = params['unitId'] as String;
      final month = params['month'] as int;
      final year = params['year'] as int;

      final startDate = DateTime(year, month, 1);
      final endDate = DateTime(year, month + 1, 0);

      final response = await client
          .from('attendance')
          .select('guard_id, type')
          .eq('worked_unit_id', unitId)
          .eq('approval_status', 'APPROVED')
          .gte('attendance_date', startDate.toIso8601String().split('T')[0])
          .lte('attendance_date', endDate.toIso8601String().split('T')[0]);

      final Map<String, Map<String, int>> summary = {};
      for (var record in (response as List)) {
        final guardId = record['guard_id'] as String;
        final type = record['type'] as String;

        summary.putIfAbsent(guardId, () => {'normal': 0, 'ot': 0});
        if (type == 'OT') {
          summary[guardId]!['ot'] = (summary[guardId]!['ot'] ?? 0) + 1;
        } else {
          summary[guardId]!['normal'] = (summary[guardId]!['normal'] ?? 0) + 1;
        }
      }
      return summary;
    });

final guardsByUnitProvider = FutureProvider.family<List<Guard>, String>((
  ref,
  unitId,
) async {
  return ref.read(guardRepositoryProvider).getGuards(unitId: unitId);
});
