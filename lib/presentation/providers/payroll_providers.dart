import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/payroll_repository.dart';

final payrollRepositoryProvider = Provider((ref) => PayrollRepository());

final isPayrollLockedProvider = FutureProvider.autoDispose
    .family<bool, ({int month, int year})>((ref, date) async {
  return ref
      .read(payrollRepositoryProvider)
      .isPayrollLocked(date.month, date.year);
});
