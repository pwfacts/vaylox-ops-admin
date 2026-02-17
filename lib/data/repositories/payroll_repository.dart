import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/salary_slip_model.dart';
import '../services/supabase_service.dart';

class PayrollRepository {
  final SupabaseClient _client = SupabaseService.client;

  Future<List<SalarySlip>> getSalarySlipsByGuard(String guardId) async {
    final response = await _client
        .from('salary_slips')
        .select()
        .eq('guard_id', guardId)
        .order('year', ascending: false)
        .order('month', ascending: false);

    return (response as List).map((json) => SalarySlip.fromJson(json)).toList();
  }

  Future<List<SalarySlip>> getSalarySlipsByUnit(
      String unitId, int month, int year) async {
    // This requires a join with guards table
    final response = await _client
        .from('salary_slips')
        .select('*, guards!inner(assigned_unit_id)')
        .eq('guards.assigned_unit_id', unitId)
        .eq('month', month)
        .eq('year', year);

    return (response as List).map((json) => SalarySlip.fromJson(json)).toList();
  }

  Future<Map<String, dynamic>> getPayrollStats() async {
    final now = DateTime.now();
    final response = await _client
        .from('salary_slips')
        .select('month, year, status, total_amount')
        .eq('year', now.year);

    // Distinct locked months
    final lockedMonths = (response as List)
        .where((r) => r['status'] == 'LOCKED' || r['status'] == 'PAID')
        .map((r) => '${r['month']}-${r['year']}')
        .toSet()
        .length;

    final totalValue = (response as List)
        .where((r) => r['status'] == 'LOCKED' || r['status'] == 'PAID')
        .fold(0.0, (sum, r) => sum + (r['total_amount'] as num).toDouble());

    return {
      'locked_months': lockedMonths,
      'total_value': totalValue,
    };
  }

  Future<bool> isPayrollLocked(int month, int year) async {
    final response = await _client
        .from('salary_slips')
        .select()
        .eq('month', month)
        .eq('year', year)
        .filter('status', 'in', ['LOCKED', 'PAID']).limit(1);

    return (response as List).isNotEmpty;
  }

  Future<void> generatePayrollDrafts(int month, int year) async {
    // 1. Check if locked
    if (await isPayrollLocked(month, year)) {
      throw Exception('Payroll for this period is already locked or paid.');
    }

    // 2. Fetch all active guards
    final guardsResponse =
        await _client.from('guards').select().eq('status', 'active');

    // Convert to list of maps
    final guards = List<Map<String, dynamic>>.from(guardsResponse as List);

    if (guards.isEmpty) return;

    // 3. For each guard, calculate salary
    // Optimized: Could use a count query instead of manual loop but loop is safer for complex logic
    // To optimize, fetch ALL attendance for this month for all guards in one go?
    // Or just group by guard_id.

    // Fetching attendance counts grouped by guard_id
    // Supabase GROUP BY support is via RPC or just fetching expected rows
    // Since we need "approved" attendance count.

    // Using a simpler approach: Loop (not scalable for 1000s but ok for <100)
    // Or use RPC if performance needed.
    // For MVP Day 10, loop is acceptable or batch.

    // Batch logic:
    final startDate = DateTime(year, month, 1).toIso8601String();
    final endDate =
        DateTime(year, month + 1, 0).toIso8601String(); // Last day of month

    // Fetch all attendance for the month
    final attendanceResponse = await _client
        .from('attendance')
        .select('guard_id')
        .eq('approval_status', 'APPROVED')
        .gte('attendance_date', startDate)
        .lte('attendance_date', endDate);

    final allAttendance =
        List<Map<String, dynamic>>.from(attendanceResponse as List);

    // Count per guard
    final Map<String, int> attendanceCounts = {};
    for (var att in allAttendance) {
      final gid = att['guard_id'] as String;
      attendanceCounts[gid] = (attendanceCounts[gid] ?? 0) + 1;
    }

    // Prepare batch insert/upsert
    final List<Map<String, dynamic>> slips = [];

    for (var guard in guards) {
      final guardId = guard['id'];
      final daysPresent = attendanceCounts[guardId] ?? 0;
      final basicSalary = (guard['basic_salary'] as num).toDouble();

      // Calculation: (Basic / 30) * Days
      // Using 30 days standard
      final dailyRate = basicSalary / 30;
      final totalAmount = (dailyRate * daysPresent).roundToDouble();

      slips.add({
        'guard_id': guardId,
        'month': month,
        'year': year,
        'basic_salary': basicSalary,
        'allowances': 0, // Placeholder
        'deductions': 0, // Placeholder
        'total_amount': totalAmount,
        'status': 'DRAFT',
        'generated_at': DateTime.now().toIso8601String(),
      });
    }

    if (slips.isNotEmpty) {
      await _client.from('salary_slips').upsert(
            slips,
            onConflict: 'guard_id, month, year', // Constraint name or columns
          );
    }
  }

  Future<void> lockPayroll(int month, int year) async {
    await _client
        .from('salary_slips')
        .update({'status': 'LOCKED'})
        .eq('month', month)
        .eq('year', year)
        .eq('status', 'DRAFT');
  }
}
