import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/supabase_service.dart';

class DashboardStats {
  final int totalGuards;
  final int totalUnits;
  final double todayAttendancePercentage;
  final double monthlyExpense;
  final Map<String, int> attendanceTypeDistribution;
  final List<ManualFallbackAlert> fallbackAlerts;

  DashboardStats({
    required this.totalGuards,
    required this.totalUnits,
    required this.todayAttendancePercentage,
    required this.monthlyExpense,
    required this.attendanceTypeDistribution,
    required this.fallbackAlerts,
  });
}

class ManualFallbackAlert {
  final String guardName;
  final double fallbackPercentage;
  final int totalDuties;

  ManualFallbackAlert({
    required this.guardName,
    required this.fallbackPercentage,
    required this.totalDuties,
  });
}

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final client = SupabaseService().client;
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);
  final todayStr = now.toIso8601String().split('T')[0];

  // 1. Total Guards & Units
  final guardsRes = await client
      .from('guards')
      .select('id')
      .eq('status', 'active')
      .count(CountOption.exact);
  final unitsRes = await client
      .from('units')
      .select('id')
      .count(CountOption.exact);

  final totalGuards = guardsRes.count;
  final totalUnits = unitsRes.count;

  // 2. Today's Attendance
  final attendanceTodayRes = await client
      .from('attendance')
      .select('id')
      .eq('attendance_date', todayStr)
      .eq('approval_status', 'APPROVED')
      .count(CountOption.exact);

  final presentToday = attendanceTodayRes.count;
  final attendancePct = totalGuards > 0
      ? (presentToday / totalGuards) * 100
      : 0.0;

  // 3. Monthly Expense (Net Pay generated)
  final slipsRes = await client
      .from('salary_slips')
      .select('net_pay')
      .eq('month', now.month)
      .eq('year', now.year);

  double totalExpense = 0;
  for (var row in (slipsRes as List)) {
    totalExpense += (row['net_pay'] as num).toDouble();
  }

  // 4. OT vs Normal Distribution (Current Month)
  final distRes = await client
      .from('attendance')
      .select('type')
      .gte('attendance_date', startOfMonth.toIso8601String().split('T')[0])
      .eq('approval_status', 'APPROVED');

  int normalCount = 0;
  int otCount = 0;
  for (var row in (distRes as List)) {
    if (row['type'] == 'OT') {
      otCount++;
    } else {
      normalCount++;
    }
  }

  // 5. Anti-Fraud (Manual Fallback Alerts)
  final fallbackRes = await client
      .from('attendance')
      .select('guard_id, attendance_method, guards(full_name)')
      .gte('attendance_date', startOfMonth.toIso8601String().split('T')[0]);

  final Map<String, Map<String, dynamic>> guardStats = {};
  for (var row in (fallbackRes as List)) {
    final gid = row['guard_id'];
    final method = row['attendance_method'];
    final name = row['guards']['full_name'];

    guardStats.putIfAbsent(gid, () => {'name': name, 'total': 0, 'manual': 0});
    guardStats[gid]!['total']++;
    if (method == 'MANUAL_FALLBACK') {
      guardStats[gid]!['manual']++;
    }
  }

  final alerts = guardStats.entries
      .map((e) {
        final total = e.value['total'] as int;
        final manual = e.value['manual'] as int;
        final pct = (manual / total) * 100;
        return ManualFallbackAlert(
          guardName: e.value['name'],
          fallbackPercentage: pct,
          totalDuties: total,
        );
      })
      .where((a) => a.fallbackPercentage > 30 && a.totalDuties >= 5)
      .toList();

  return DashboardStats(
    totalGuards: totalGuards,
    totalUnits: totalUnits,
    todayAttendancePercentage: attendancePct,
    monthlyExpense: totalExpense,
    attendanceTypeDistribution: {'Normal': normalCount, 'OT': otCount},
    fallbackAlerts: alerts,
  );
});
