import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/salary_slip_model.dart';
import '../services/supabase_service.dart';

class PayrollRepository {
  final SupabaseClient _client = SupabaseService().client;

  Future<List<SalarySlip>> getSalarySlipsByGuard(String guardId) async {
    final response = await _client
        .from('salary_slips')
        .select()
        .eq('guard_id', guardId)
        .order('year', ascending: false)
        .order('month', ascending: false);

    return (response as List).map((json) => SalarySlip.fromJson(json)).toList();
  }

  Future<List<SalarySlip>> getSalarySlipsByUnit(String unitId, int month, int year) async {
    // This requires a join with guards table
    final response = await _client
        .from('salary_slips')
        .select('*, guards!inner(assigned_unit_id)')
        .eq('guards.assigned_unit_id', unitId)
        .eq('month', month)
        .eq('year', year);

    return (response as List).map((json) => SalarySlip.fromJson(json)).toList();
  }

  Future<void> updateSlipStatus(String slipId, String status) async {
    await _client.from('salary_slips').update({'status': status}).eq('id', slipId);
  }
}
