import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/guard_model.dart';
import '../models/attendance_model.dart';
import '../models/salary_slip_model.dart';
import '../services/supabase_service.dart';

class SalaryCalculationService {
  final SupabaseClient _client = SupabaseService().client;

  Future<Map<String, dynamic>> getPayrollSettings(String companyId) async {
    final response = await _client
        .from('payroll_settings')
        .select()
        .eq('company_id', companyId)
        .single();
    return response;
  }

  Future<SalarySlip> calculateMonthlySalary({
    required Guard guard,
    required int month,
    required int year,
    int? manualCalculationDays,
    int? manualPresentDays,
    int? manualOtDays,
    double? manualBasic,
    double? manualOtBasic,
    double? manualOtAmount,
    String? overrideBy,
    String? overrideNote,
    double uniformDeduction = 0,
    double penaltyDeduction = 0,
    double canteenDeduction = 0,
    double advanceDeduction = 0,
    double otherDed1 = 0,
    double otherDed2 = 0,
  }) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0); // Last day of month
    final totalDaysInMonth = endDate.day;

    // 1. Fetch all APPROVED attendance for the month with unit name join
    final attendanceResponse = await _client
        .from('attendance')
        .select('*, units(name)')
        .eq('guard_id', guard.id)
        .eq('approval_status', 'APPROVED')
        .gte('attendance_date', startDate.toIso8601String().split('T')[0])
        .lte('attendance_date', endDate.toIso8601String().split('T')[0]);

    final List<Attendance> attendanceRecords = (attendanceResponse as List)
        .map((json) => Attendance.fromJson(json))
        .toList();

    // 2. Count duties by type (NORMAL vs OT)
    // Rule: IF worked_unit_id == primary_unit_id → NORMAL ELSE → OT
    int normalDutiesCount = 0;
    int otDutiesCount = 0;

    for (var record in attendanceRecords) {
      if (record.type == AttendanceType.ot ||
          (record.workedUnitId != null &&
              record.workedUnitId != record.primaryUnitId)) {
        otDutiesCount++;
      } else {
        normalDutiesCount++;
      }
    }

    final presentDaysCountSug = normalDutiesCount;
    final otDaysCountSug = otDutiesCount;
    final baseDaysForSalary = manualCalculationDays ?? totalDaysInMonth;

    final finalPresentDays = manualPresentDays ?? presentDaysCountSug;
    final finalOtDays = manualOtDays ?? otDaysCountSug;
    final absentDaysCount = max(0, baseDaysForSalary - finalPresentDays);

    // 3. Get Payroll Settings
    final settings = await getPayrollSettings(guard.companyId);
    final double pfRate = (settings['pf_percentage'] as num).toDouble() / 100;
    final double esicRate =
        (settings['esic_percentage'] as num).toDouble() / 100;
    final double ptAmount = (settings['professional_tax'] as num).toDouble();
    final double lwfAmount = (settings['lwf_amount'] as num).toDouble();

    // 4. Calculate Earnings
    final double fixedBasic = manualBasic ?? guard.basicSalary;
    final double perDaySalary = fixedBasic / baseDaysForSalary;
    final double earnedBasic = perDaySalary * finalPresentDays;

    final double otBasic = manualOtBasic ?? guard.basicSalary;
    final double otPerDay = otBasic / baseDaysForSalary;
    final double suggestedOtAmount = otPerDay * finalOtDays;
    final double earnedOt = manualOtAmount ?? suggestedOtAmount;

    const double otherAllowances = 0;
    final double grossPay = earnedBasic + earnedOt + otherAllowances;

    // 5. Calculate Deductions with refined logic
    double pfDeduction = 0;
    if (guard.isPfEnabled) {
      final double pfBase = min(earnedBasic, 15000);
      pfDeduction = pfBase * pfRate;
    }

    double esicDeduction = 0;
    if (guard.isEsicEnabled && grossPay <= 21000) {
      esicDeduction = grossPay * esicRate;
    }

    double ptDeduction = 0;
    if (guard.isPtEnabled && grossPay >= 12000) {
      ptDeduction = ptAmount;
    }

    final List<dynamic>? lwfMonths = settings['lwf_months'];
    final bool isLwfMonth = lwfMonths?.contains(month) ?? false;
    final double lwfActual = isLwfMonth ? lwfAmount : 0;

    final double totalDeductions =
        pfDeduction +
        esicDeduction +
        ptDeduction +
        lwfActual +
        uniformDeduction +
        penaltyDeduction +
        canteenDeduction +
        advanceDeduction +
        otherDed1 +
        otherDed2;

    // 6. Net Pay
    final double netPay = grossPay - totalDeductions;

    return SalarySlip(
      id: '',
      companyId: guard.companyId,
      guardId: guard.id,
      month: month,
      year: year,
      totalWorkingDays: baseDaysForSalary,
      presentDays: finalPresentDays,
      absentDays: absentDaysCount,
      basicPay: earnedBasic,
      otPay: earnedOt,
      otherAllowances: otherAllowances,
      grossPay: grossPay,
      pfDeduction: pfDeduction,
      esicDeduction: esicDeduction,
      ptDeduction: ptDeduction,
      lwfDeduction: lwfActual,
      advanceDeduction: advanceDeduction,
      uniformDeduction: uniformDeduction,
      penaltyDeduction: penaltyDeduction,
      canteenDeduction: canteenDeduction,
      otherDed1: otherDed1,
      otherDed2: otherDed2,
      totalDeductions: totalDeductions,
      netPay: netPay,
      manualOverrideBy: overrideBy,
      manualOverrideAt:
          (manualPresentDays != null ||
              manualOtDays != null ||
              manualBasic != null)
          ? DateTime.now()
          : null,
      manualOverrideNote: overrideNote,
      attendanceSuggestedDays: presentDaysCountSug,
      attendanceSuggestedOtDays: otDaysCountSug,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> saveSalarySlip(SalarySlip slip) async {
    final data = slip.toJson();
    data.remove('id'); // Let Supabase generate it
    await _client
        .from('salary_slips')
        .upsert(data, onConflict: 'guard_id,month,year');
  }
}
