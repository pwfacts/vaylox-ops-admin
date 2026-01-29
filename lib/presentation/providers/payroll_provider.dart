import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/guard_model.dart';
import '../../data/models/salary_slip_model.dart';
import '../../data/services/salary_calculation_service.dart';
import '../../data/services/export_service.dart';
import '../../data/services/pdf_service.dart';
import '../../data/repositories/payroll_repository.dart';

class PayrollState {
  final bool isLoading;
  final String? error;
  final List<SalarySlip> activeMonthSlips;

  PayrollState({this.isLoading = false, this.error, this.activeMonthSlips = const []});
}

class PayrollNotifier extends StateNotifier<PayrollState> {
  final SalaryCalculationService _service = SalaryCalculationService();
  final PayrollRepository _repository = PayrollRepository();
  final ExportService _exportService = ExportService();
  final PdfService _pdfService = PdfService();

  PayrollNotifier() : super(PayrollState());

  Future<void> runPayrollForGuard({
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
    double canteenDeduction = 0,
    double penaltyDeduction = 0,
    double advanceDeduction = 0,
    double uniformDeduction = 0,
    double otherDed1 = 0,
    double otherDed2 = 0,
  }) async {
    state = PayrollState(isLoading: true);
    try {
      final slip = await _service.calculateMonthlySalary(
        guard: guard,
        month: month,
        year: year,
        manualCalculationDays: manualCalculationDays,
        manualPresentDays: manualPresentDays,
        manualOtDays: manualOtDays,
        manualBasic: manualBasic,
        manualOtBasic: manualOtBasic,
        manualOtAmount: manualOtAmount,
        overrideBy: overrideBy,
        overrideNote: overrideNote,
        canteenDeduction: canteenDeduction,
        penaltyDeduction: penaltyDeduction,
        advanceDeduction: advanceDeduction,
        uniformDeduction: uniformDeduction,
        otherDed1: otherDed1,
        otherDed2: otherDed2,
      );
      await _service.saveSalarySlip(slip);
      
      // Update local state by adding/replacing this slip in the list
      final currentSlips = List<SalarySlip>.from(state.activeMonthSlips);
      final index = currentSlips.indexWhere((s) => s.guardId == guard.id && s.month == month && s.year == year);
      if (index != -1) {
        currentSlips[index] = slip;
      } else {
        currentSlips.add(slip);
      }

      state = PayrollState(isLoading: false, activeMonthSlips: currentSlips);
    } catch (e) {
      state = PayrollState(isLoading: false, error: e.toString());
    }
  }

  Future<void> runPayrollForUnit({
    required List<Guard> guards,
    required int month,
    required int year,
  }) async {
    state = PayrollState(isLoading: true);
    
    try {
      final List<SalarySlip> generatedSlips = [];
      for (var guard in guards) {
        final slip = await _service.calculateMonthlySalary(
          guard: guard,
          month: month,
          year: year,
        );
        await _service.saveSalarySlip(slip);
        generatedSlips.add(slip);
      }
      
      state = PayrollState(isLoading: false, activeMonthSlips: generatedSlips);
    } catch (e) {
      state = PayrollState(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadSlipsForUnit(String unitId, int month, int year) async {
    state = PayrollState(isLoading: true);
    try {
      final slips = await _repository.getSalarySlipsByUnit(unitId, month, year);
      state = PayrollState(isLoading: false, activeMonthSlips: slips);
    } catch (e) {
      state = PayrollState(isLoading: false, error: e.toString());
    }
  }

  Future<void> exportToExcel({
    required List<Guard> guards,
    required String unitName,
    required int month,
    required int year,
  }) async {
    if (state.activeMonthSlips.isEmpty) return;
    
    try {
      await _exportService.exportMonthlyPayroll(
        slips: state.activeMonthSlips,
        guards: guards,
        unitName: unitName,
        month: month,
        year: year,
      );
    } catch (e) {
      state = PayrollState(activeMonthSlips: state.activeMonthSlips, error: 'Export failed: $e');
    }
  }

  Future<void> printSlip(SalarySlip slip, Guard guard) async {
    try {
      await _pdfService.generateAndPrintSlip(
        slip: slip,
        guard: guard,
        companyName: 'JDS SAFE GUARD & MANAGEMENT PVT. LTD.',
      );
    } catch (e) {
      state = PayrollState(activeMonthSlips: state.activeMonthSlips, error: 'PDF failed: $e');
    }
  }

  Future<void> markAsPaid(SalarySlip slip) async {
    try {
      final updatedSlip = slip.copyWith(
        status: 'paid',
        paymentDate: DateTime.now(),
        paymentMethod: 'Bank Transfer', // Default
      );
      await _service.saveSalarySlip(updatedSlip);
      
      final currentSlips = List<SalarySlip>.from(state.activeMonthSlips);
      final index = currentSlips.indexWhere((s) => s.id == slip.id);
      if (index != -1) {
        currentSlips[index] = updatedSlip;
        state = PayrollState(activeMonthSlips: currentSlips);
      }
    } catch (e) {
      state = PayrollState(activeMonthSlips: state.activeMonthSlips, error: 'Payment update failed: $e');
    }
  }
}

final payrollProvider = StateNotifierProvider<PayrollNotifier, PayrollState>((ref) {
  return PayrollNotifier();
});

final guardSlipsProvider = FutureProvider.family<List<SalarySlip>, String>((ref, guardId) async {
  return PayrollRepository().getSalarySlipsByGuard(guardId);
});
