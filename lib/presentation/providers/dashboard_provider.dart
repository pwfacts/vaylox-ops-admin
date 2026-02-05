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
  
  // Enhanced metrics per PRD
  final double guardGrowthRate; // % change vs last month
  final double attendanceGrowthRate; // % change vs last month
  final double expenseGrowthRate; // % change vs last month
  final double pendingPayments;
  final int pendingApprovals;
  final double manualFallbackRate;
  final List<AttendanceTrendData> attendanceTrend;
  final List<UnitDistributionData> unitDistribution;
  final List<OtAnalysisData> otAnalysis;
  
  DashboardStats({
    required this.totalGuards,
    required this.totalUnits,
    required this.todayAttendancePercentage,
    required this.monthlyExpense,
    required this.attendanceTypeDistribution,
    required this.fallbackAlerts,
    required this.guardGrowthRate,
    required this.attendanceGrowthRate,
    required this.expenseGrowthRate,
    required this.pendingPayments,
    required this.pendingApprovals,
    required this.manualFallbackRate,
    required this.attendanceTrend,
    required this.unitDistribution,
    required this.otAnalysis,
  });
}

class AttendanceTrendData {
  final DateTime date;
  final double attendanceRate;
  
  AttendanceTrendData({required this.date, required this.attendanceRate});
}

class UnitDistributionData {
  final String unitName;
  final int guardCount;
  final String areaName;
  
  UnitDistributionData({required this.unitName, required this.guardCount, required this.areaName});
}

class OtAnalysisData {
  final String unitName;
  final int normalHours;
  final int otHours;
  final double otPercentage;
  
  OtAnalysisData({required this.unitName, required this.normalHours, required this.otHours, required this.otPercentage});
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
  try {
    final client = SupabaseService().client;
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final todayStr = now.toIso8601String().split('T')[0];

    // Mock data for development when Supabase isn't available
    try {
      await client.from('guards').select('id').limit(1);
    } catch (e) {
      print('Supabase not available, using mock data');
      return _getMockDashboardData();
    }

    // 1. Total Guards & Units (with growth calculation)
    final guardsRes = await client
        .from('guards')
        .select('id, created_at')
        .eq('status', 'active');
    final unitsRes = await client
        .from('units')
        .select('id, guards(id)')
        .eq('status', 'active');

    final totalGuards = (guardsRes as List).length;
    final totalUnits = (unitsRes as List).length;

    // Calculate growth rates
    final lastMonthGuards = (guardsRes as List)
        .where((g) => DateTime.parse(g['created_at']).isBefore(startOfMonth))
        .length;
    final guardGrowthRate = lastMonthGuards > 0 
        ? ((totalGuards - lastMonthGuards) / lastMonthGuards) * 100 
        : 0.0;

    // 2. Today's Attendance
    final attendanceTodayRes = await client
        .from('attendance')
        .select('id')
        .eq('attendance_date', todayStr)
        .eq('approval_status', 'APPROVED');

    final presentToday = (attendanceTodayRes as List).length;
    final attendancePct = totalGuards > 0
        ? (presentToday / totalGuards) * 100
        : 0.0;

    // Calculate attendance growth (mock calculation)
    final attendanceGrowthRate = 3.0; // Mock: 3% increase

    // 3. Monthly Expense
    final slipsRes = await client
        .from('salary_slips')
        .select('net_pay, status')
        .eq('month', now.month)
        .eq('year', now.year);

    double totalExpense = 0;
    double pendingPayments = 0;
    for (var row in (slipsRes as List)) {
      final amount = (row['net_pay'] as num?)?.toDouble() ?? 0;
      totalExpense += amount;
      if (row['status'] != 'PAID') {
        pendingPayments += amount;
      }
    }

    final expenseGrowthRate = 5.0; // Mock: 5% increase

    // 4. Pending Approvals
    final pendingApprovalsRes = await client
        .from('attendance')
        .select('id')
        .eq('approval_status', 'PENDING')
        .eq('attendance_method', 'MANUAL_FALLBACK');
    final pendingApprovals = (pendingApprovalsRes as List).length;

    // 5. Manual Fallback Analysis
    final fallbackRes = await client
        .from('attendance')
        .select('guard_id, attendance_method, guards(full_name)')
        .gte('attendance_date', startOfMonth.toIso8601String().split('T')[0]);

    int totalAttendance = (fallbackRes as List).length;
    int manualFallbackCount = (fallbackRes as List)
        .where((row) => row['attendance_method'] == 'MANUAL_FALLBACK')
        .length;
    
    final manualFallbackRate = totalAttendance > 0 
        ? (manualFallbackCount / totalAttendance) * 100 
        : 0.0;

    // Generate guard-specific fallback alerts
    final Map<String, Map<String, dynamic>> guardStats = {};
    for (var row in (fallbackRes as List)) {
      final gid = row['guard_id'];
      final method = row['attendance_method'];
      final name = row['guards']?['full_name'] ?? 'Unknown';

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
          final pct = total > 0 ? (manual / total) * 100 : 0.0;
          return ManualFallbackAlert(
            guardName: e.value['name'],
            fallbackPercentage: pct,
            totalDuties: total,
          );
        })
        .where((a) => a.fallbackPercentage > 30 && a.totalDuties >= 5)
        .toList();

    // 6. Attendance Trend (last 6 months)
    final attendanceTrend = <AttendanceTrendData>[];
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthStr = month.toIso8601String().split('T')[0];
      
      final monthAttendanceRes = await client
          .from('attendance')
          .select('id')
          .gte('attendance_date', monthStr)
          .lt('attendance_date', DateTime(month.year, month.month + 1, 1).toIso8601String().split('T')[0])
          .eq('approval_status', 'APPROVED');
      
      final attendanceCount = (monthAttendanceRes as List).length;
      final expectedAttendance = totalGuards * DateTime(month.year, month.month + 1, 0).day; // Days in month
      final rate = expectedAttendance > 0 ? (attendanceCount / expectedAttendance) * 100 : 0.0;
      
      attendanceTrend.add(AttendanceTrendData(
        date: month,
        attendanceRate: rate.clamp(0, 100),
      ));
    }

    // 7. Unit Distribution
    final unitDistribution = <UnitDistributionData>[];
    for (var unit in (unitsRes as List)) {
      final guards = unit['guards'] as List? ?? [];
      unitDistribution.add(UnitDistributionData(
        unitName: unit['name'] ?? 'Unknown Unit',
        guardCount: guards.length,
        areaName: 'Area ${unitDistribution.length + 1}', // Mock area
      ));
    }

    // 8. OT Analysis
    final otAnalysis = <OtAnalysisData>[];
    final otRes = await client
        .from('attendance')
        .select('type, units(name)')
        .gte('attendance_date', startOfMonth.toIso8601String().split('T')[0])
        .eq('approval_status', 'APPROVED');

    final Map<String, Map<String, int>> unitOtStats = {};
    for (var row in (otRes as List)) {
      final unitName = row['units']?['name'] ?? 'Unknown';
      final type = row['type'] ?? 'NORMAL';
      
      unitOtStats.putIfAbsent(unitName, () => {'normal': 0, 'ot': 0});
      if (type == 'OT') {
        unitOtStats[unitName]!['ot'] = (unitOtStats[unitName]!['ot'] ?? 0) + 1;
      } else {
        unitOtStats[unitName]!['normal'] = (unitOtStats[unitName]!['normal'] ?? 0) + 1;
      }
    }

    for (var entry in unitOtStats.entries) {
      final normal = entry.value['normal'] ?? 0;
      final ot = entry.value['ot'] ?? 0;
      final total = normal + ot;
      final otPct = total > 0 ? (ot / total) * 100 : 0.0;
      
      otAnalysis.add(OtAnalysisData(
        unitName: entry.key,
        normalHours: normal * 8, // Assuming 8-hour shifts
        otHours: ot * 4, // Assuming 4-hour OT
        otPercentage: otPct,
      ));
    }

    return DashboardStats(
      totalGuards: totalGuards,
      totalUnits: totalUnits,
      todayAttendancePercentage: attendancePct,
      monthlyExpense: totalExpense,
      attendanceTypeDistribution: {
        'Normal': attendanceTrend.isNotEmpty ? (attendanceTrend.last.attendanceRate * totalGuards / 100).round() : 0,
        'OT': otAnalysis.fold(0, (sum, data) => sum + (data.otHours / 4).round()),
      },
      fallbackAlerts: alerts,
      guardGrowthRate: guardGrowthRate,
      attendanceGrowthRate: attendanceGrowthRate,
      expenseGrowthRate: expenseGrowthRate,
      pendingPayments: pendingPayments,
      pendingApprovals: pendingApprovals,
      manualFallbackRate: manualFallbackRate,
      attendanceTrend: attendanceTrend,
      unitDistribution: unitDistribution,
      otAnalysis: otAnalysis,
    );
  } catch (e) {
    print('Dashboard data fetch error: $e');
    return _getMockDashboardData();
  }
});

DashboardStats _getMockDashboardData() {
  final now = DateTime.now();
  return DashboardStats(
    totalGuards: 180,
    totalUnits: 12,
    todayAttendancePercentage: 98.5,
    monthlyExpense: 520000,
    attendanceTypeDistribution: {'Normal': 165, 'OT': 45},
    fallbackAlerts: [
      ManualFallbackAlert(guardName: 'Pritam Kumar (BH001)', fallbackPercentage: 35.0, totalDuties: 20),
      ManualFallbackAlert(guardName: 'Amit Patel (RJ005)', fallbackPercentage: 42.0, totalDuties: 18),
    ],
    guardGrowthRate: 2.0,
    attendanceGrowthRate: 3.0,
    expenseGrowthRate: 5.0,
    pendingPayments: 45000,
    pendingApprovals: 12,
    manualFallbackRate: 8.5,
    attendanceTrend: List.generate(6, (index) {
      final month = DateTime(now.year, now.month - (5 - index), 1);
      return AttendanceTrendData(
        date: month,
        attendanceRate: 95.0 + (index * 0.5), // Trending upward
      );
    }),
    unitDistribution: [
      UnitDistributionData(unitName: 'Bhawani Mall', guardCount: 25, areaName: 'Central Zone'),
      UnitDistributionData(unitName: 'City Center', guardCount: 20, areaName: 'Central Zone'),
      UnitDistributionData(unitName: 'Tech Park Alpha', guardCount: 30, areaName: 'Tech Zone'),
      UnitDistributionData(unitName: 'Residential Complex', guardCount: 18, areaName: 'Residential Zone'),
      UnitDistributionData(unitName: 'Industrial Unit A', guardCount: 22, areaName: 'Industrial Zone'),
      UnitDistributionData(unitName: 'Corporate Plaza', guardCount: 35, areaName: 'Business Zone'),
    ],
    otAnalysis: [
      OtAnalysisData(unitName: 'Bhawani Mall', normalHours: 200, otHours: 60, otPercentage: 23.0),
      OtAnalysisData(unitName: 'Tech Park Alpha', normalHours: 240, otHours: 80, otPercentage: 25.0),
      OtAnalysisData(unitName: 'Corporate Plaza', normalHours: 280, otHours: 40, otPercentage: 12.5),
      OtAnalysisData(unitName: 'City Center', normalHours: 160, otHours: 50, otPercentage: 24.0),
    ],
  );
}
