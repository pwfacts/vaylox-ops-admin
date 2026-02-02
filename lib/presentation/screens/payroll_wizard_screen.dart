import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/guard_model.dart';
import '../../data/models/salary_slip_model.dart';
import '../providers/attendance_provider.dart';
import '../providers/payroll_provider.dart';
import '../../data/services/supabase_service.dart';
import '../screens/monthly_attendance_log_screen.dart';

class PayrollWizardScreen extends ConsumerStatefulWidget {
  final String unitId;
  final String unitName;

  const PayrollWizardScreen({
    super.key,
    required this.unitId,
    required this.unitName,
  });

  @override
  ConsumerState<PayrollWizardScreen> createState() =>
      _PayrollWizardScreenState();
}

class _PayrollWizardScreenState extends ConsumerState<PayrollWizardScreen> {
  DateTime _selectedMonth = DateTime.now();
  final TextEditingController _unitCalculationDaysController =
      TextEditingController(text: '30');
  final Map<String, TextEditingController> _calcDaysControllers = {};
  final Map<String, TextEditingController> _basicControllers = {};
  final Map<String, TextEditingController> _presentDaysControllers = {};
  final Map<String, TextEditingController> _otDaysControllers = {};
  final Map<String, TextEditingController> _otBasicControllers = {};
  final Map<String, TextEditingController> _otAmountControllers = {};
  final Map<String, TextEditingController> _canteenControllers = {};
  final Map<String, TextEditingController> _penaltyControllers = {};
  final Map<String, TextEditingController> _advanceControllers = {};
  final Map<String, TextEditingController> _uniformControllers = {};
  final Map<String, TextEditingController> _otherDed1Controllers = {};
  final Map<String, TextEditingController> _otherDed2Controllers = {};
  final Map<String, TextEditingController> _overrideNoteControllers = {};
  final Map<String, bool> _pfToggles = {};
  final Map<String, bool> _ptToggles = {};

  @override
  void dispose() {
    for (var c in _basicControllers.values) {
      c.dispose();
    }
    for (var c in _otDaysControllers.values) {
      c.dispose();
    }
    for (var c in _otBasicControllers.values) {
      c.dispose();
    }
    for (var c in _otAmountControllers.values) {
      c.dispose();
    }
    for (var c in _penaltyControllers.values) {
      c.dispose();
    }
    for (var c in _canteenControllers.values) {
      c.dispose();
    }
    for (var c in _calcDaysControllers.values) {
      c.dispose();
    }
    _unitCalculationDaysController.dispose();
    super.dispose();
  }

  TextEditingController _getCalcDaysController(String guardId) {
    return _calcDaysControllers.putIfAbsent(
      guardId,
      () => TextEditingController(text: _unitCalculationDaysController.text),
    );
  }

  TextEditingController _getBasicController(
    String guardId,
    double initialValue,
  ) {
    return _basicControllers.putIfAbsent(
      guardId,
      () => TextEditingController(text: initialValue.toStringAsFixed(0)),
    );
  }

  TextEditingController _getPresentDaysController(
    String guardId,
    int initialValue,
  ) {
    return _presentDaysControllers.putIfAbsent(
      guardId,
      () => TextEditingController(text: initialValue.toString()),
    );
  }

  TextEditingController _getOtDaysController(String guardId, int initialValue) {
    return _otDaysControllers.putIfAbsent(
      guardId,
      () => TextEditingController(text: initialValue.toString()),
    );
  }

  TextEditingController _getOtBasicController(
    String guardId,
    double initialValue,
  ) {
    return _otBasicControllers.putIfAbsent(
      guardId,
      () => TextEditingController(text: initialValue.toStringAsFixed(0)),
    );
  }

  TextEditingController _getOtAmountController(String guardId) {
    return _otAmountControllers.putIfAbsent(
      guardId,
      () => TextEditingController(text: ''),
    );
  }

  TextEditingController _getCanteenController(String guardId) {
    return _canteenControllers.putIfAbsent(
      guardId,
      () => TextEditingController(text: '0'),
    );
  }

  TextEditingController _getPenaltyController(String guardId) {
    return _penaltyControllers.putIfAbsent(
      guardId,
      () => TextEditingController(text: '0'),
    );
  }

  TextEditingController _getAdvanceController(String guardId) {
    return _advanceControllers.putIfAbsent(
      guardId,
      () => TextEditingController(text: '0'),
    );
  }

  TextEditingController _getUniformController(String guardId) {
    return _uniformControllers.putIfAbsent(
      guardId,
      () => TextEditingController(text: '0'),
    );
  }

  TextEditingController _getOtherDed1Controller(String guardId) {
    return _otherDed1Controllers.putIfAbsent(
      guardId,
      () => TextEditingController(text: '0'),
    );
  }

  TextEditingController _getOtherDed2Controller(String guardId) {
    return _otherDed2Controllers.putIfAbsent(
      guardId,
      () => TextEditingController(text: '0'),
    );
  }

  TextEditingController _getOverrideNoteController(String guardId) {
    return _overrideNoteControllers.putIfAbsent(
      guardId,
      () => TextEditingController(text: 'Manual adjustment confirmed'),
    );
  }

  bool _getPfToggle(String guardId, bool initialValue) {
    return _pfToggles.putIfAbsent(guardId, () => initialValue);
  }

  bool _getPtToggle(String guardId, bool initialValue) {
    return _ptToggles.putIfAbsent(guardId, () => initialValue);
  }

  @override
  Widget build(BuildContext context) {
    final payrollState = ref.watch(payrollProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll Wizard'),
        actions: [
          if (payrollState.activeMonthSlips.isNotEmpty)
            TextButton.icon(
              onPressed: () => _exportDetailedExcel(),
              icon: const Icon(Icons.file_download, color: Colors.greenAccent),
              label: const Text(
                'Export Excel',
                style: TextStyle(color: Colors.greenAccent),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Processing for: ${widget.unitName}',
              style: AppTextStyles.heading2,
            ),
            const SizedBox(height: 8),
            Text(
              'Generate salary slips for approved attendance.',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 32),

            _buildMonthPicker(),
            const SizedBox(height: 24),
            _buildUnitSettings(),
            const SizedBox(height: 32),

            if (payrollState.isLoading)
              const Center(child: CircularProgressIndicator())
            else
              _buildActionButton(),

            if (payrollState.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Error: ${payrollState.error}',
                  style: const TextStyle(color: AppColors.error),
                ),
              ),

            const SizedBox(height: 32),
            if (payrollState.activeMonthSlips.isNotEmpty)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Generated Slips: ${payrollState.activeMonthSlips.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        itemCount: payrollState.activeMonthSlips.length,
                        itemBuilder: (context, index) {
                          // Note: For actual processing, we need the GUARD objects
                          // Here we use the list of guards from guardsByUnitProvider
                          return const SizedBox.shrink(); // Handled by guards iterator in _buildGuardAdjustmentList
                        },
                      ),
                    ),
                    Expanded(child: _buildGuardAdjustmentList()),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthPicker() {
    final monthStr = DateFormat('MMMM yyyy').format(_selectedMonth);
    return InkWell(
      onTap: () async {
        // Simple month picker logic
        final now = DateTime.now();
        final selected = await showDatePicker(
          context: context,
          initialDate: _selectedMonth,
          firstDate: DateTime(2023),
          lastDate: now,
          helpText: 'Select Payroll Month',
        );
        if (selected != null) {
          setState(() => _selectedMonth = selected);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(13),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withAlpha(26)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selected Month',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  monthStr,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Icon(Icons.calendar_month, color: AppColors.primaryBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitSettings() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withAlpha(13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryBlue.withAlpha(51)),
      ),
      child: Row(
        children: [
          const Icon(Icons.settings, color: AppColors.primaryBlue),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Base Salary Days (Unit Wide):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            width: 80,
            child: TextFormField(
              controller: _unitCalculationDaysController,
              decoration: const InputDecoration(hintText: '30'),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              onChanged: (v) {
                // Optionally update all guards who haven't manually changed it
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return const SizedBox.shrink(); // Action is moved inside the adjustment list
  }

  Widget _buildGuardAdjustmentList() {
    final guardsAsync = ref.watch(guardsByUnitProvider(widget.unitId));
    final payrollState = ref.watch(payrollProvider);
    final summaryAsync = ref.watch(
      unitAttendanceSummaryProvider({
        'unitId': widget.unitId,
        'month': _selectedMonth.month,
        'year': _selectedMonth.year,
      }),
    );

    return guardsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error loading guards: $e')),
      data: (guards) => summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error loading summary: $e')),
        data: (summary) => ListView.builder(
          itemCount: guards.length,
          itemBuilder: (context, index) {
            final guard = guards[index];
            final initialBasic = (guard.basicSalary);
            final guardSummary = summary[guard.id] ?? {'normal': 0, 'ot': 0};

            // Find if we already have a calculated slip for this guard to show suggestions
            final SalarySlip? existingSlip = payrollState.activeMonthSlips
                .cast<SalarySlip?>()
                .firstWhere((s) => s?.guardId == guard.id, orElse: () => null);

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                guard.fullName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                guard.designation
                                    .replaceAll('_', ' ')
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.blueAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.history,
                            color: Colors.blueAccent,
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MonthlyAttendanceLogScreen(
                                guardId: guard.id,
                                guardName: guard.fullName,
                                month: _selectedMonth.month,
                                year: _selectedMonth.year,
                              ),
                            ),
                          ),
                        ),
                        if (existingSlip != null)
                          IconButton(
                            icon: const Icon(
                              Icons.picture_as_pdf,
                              color: Colors.orangeAccent,
                            ),
                            onPressed: () => ref
                                .read(payrollProvider.notifier)
                                .printSlip(existingSlip, guard),
                            tooltip: 'Print Salary Slip',
                          ),
                      ],
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          _suggestionChip(
                            'Suggest Normal: ${guardSummary['normal']}',
                          ),
                          const SizedBox(width: 8),
                          _suggestionChip('Suggest OT: ${guardSummary['ot']}'),
                          const Spacer(),
                          if (existingSlip != null)
                            Row(
                              children: [
                                Text(
                                  'Net: ₹${existingSlip.netPay.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: existingSlip.status == 'paid'
                                        ? Colors.green.withAlpha(51)
                                        : Colors.red.withAlpha(51),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    existingSlip.status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: existingSlip.status == 'paid'
                                          ? Colors.green
                                          : Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (existingSlip.status != 'paid')
                                  IconButton(
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                      size: 20,
                                      color: Colors.green,
                                    ),
                                    onPressed: () => ref
                                        .read(payrollProvider.notifier)
                                        .markAsPaid(existingSlip),
                                    tooltip: 'Mark as Paid',
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.only(left: 8),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _getCalcDaysController(guard.id),
                            decoration: const InputDecoration(
                              labelText: 'Calculation Days',
                              hintText: '30/26/etc',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _getBasicController(
                              guard.id,
                              initialBasic,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Basic Salary (Manual)',
                              prefixText: '₹',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _getPresentDaysController(
                              guard.id,
                              guardSummary['normal'] ?? 0,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Present Days (Manual)',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _getOtDaysController(
                              guard.id,
                              guardSummary['ot'] ?? 0,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'OT Days (Manual)',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _getOtBasicController(
                              guard.id,
                              initialBasic,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'OT Basic (Manual)',
                              prefixText: '₹',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _getOtAmountController(guard.id),
                            decoration: const InputDecoration(
                              labelText: 'Fixed OT Amount',
                              hintText: 'Override calc',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _getCanteenController(guard.id),
                            decoration: const InputDecoration(
                              labelText: 'Canteen',
                              prefixText: '₹',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _getPenaltyController(guard.id),
                            decoration: const InputDecoration(
                              labelText: 'Penalty',
                              prefixText: '₹',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _getAdvanceController(guard.id),
                            decoration: const InputDecoration(
                              labelText: 'Advance',
                              prefixText: '₹',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _getUniformController(guard.id),
                            decoration: const InputDecoration(
                              labelText: 'Uniform',
                              prefixText: '₹',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _getOtherDed1Controller(guard.id),
                            decoration: const InputDecoration(
                              labelText: 'Other Ded 1',
                              prefixText: '₹',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _getOtherDed2Controller(guard.id),
                            decoration: const InputDecoration(
                              labelText: 'Other Ded 2',
                              prefixText: '₹',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            title: const Text(
                              'PF (12%)',
                              style: TextStyle(fontSize: 12),
                            ),
                            value: _getPfToggle(guard.id, guard.isPfEnabled),
                            onChanged: (v) =>
                                setState(() => _pfToggles[guard.id] = v),
                          ),
                        ),
                        Expanded(
                          child: SwitchListTile(
                            title: const Text(
                              'PT (₹200)',
                              style: TextStyle(fontSize: 12),
                            ),
                            value: _getPtToggle(guard.id, guard.isPtEnabled),
                            onChanged: (v) =>
                                setState(() => _ptToggles[guard.id] = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _getOverrideNoteController(guard.id),
                      decoration: const InputDecoration(
                        labelText: 'Audit Note / Reason',
                        hintText: 'Explain why days/amount changed',
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _runPayrollForGuard(guard),
                      child: const Text('Generate Slip for this Guard'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _exportDetailedExcel() async {
    final guardsAsync = ref.read(guardsByUnitProvider(widget.unitId));
    guardsAsync.whenData((guards) {
      ref
          .read(payrollProvider.notifier)
          .exportToExcel(
            guards: guards,
            unitName: widget.unitName,
            month: _selectedMonth.month,
            year: _selectedMonth.year,
          );
    });
  }

  Widget _suggestionChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withAlpha(26),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.blueAccent.withAlpha(77)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.blueAccent),
      ),
    );
  }

  Future<void> _runPayrollForGuard(Guard guard) async {
    final calcDays =
        int.tryParse(_calcDaysControllers[guard.id]?.text ?? '') ??
        int.tryParse(_unitCalculationDaysController.text) ??
        30;

    final presentDays = int.tryParse(
      _presentDaysControllers[guard.id]?.text ?? '',
    );
    final otDays = int.tryParse(_otDaysControllers[guard.id]?.text ?? '');

    final basic =
        double.tryParse(_basicControllers[guard.id]?.text ?? '0') ?? 0;
    final otBasic =
        double.tryParse(_otBasicControllers[guard.id]?.text ?? '0') ?? 0;
    final otAmount = double.tryParse(
      _otAmountControllers[guard.id]?.text ?? '',
    );

    final canteen =
        double.tryParse(_canteenControllers[guard.id]?.text ?? '0') ?? 0;
    final penalty =
        double.tryParse(_penaltyControllers[guard.id]?.text ?? '0') ?? 0;
    final advance =
        double.tryParse(_advanceControllers[guard.id]?.text ?? '0') ?? 0;
    final uniform =
        double.tryParse(_uniformControllers[guard.id]?.text ?? '0') ?? 0;
    final other1 =
        double.tryParse(_otherDed1Controllers[guard.id]?.text ?? '0') ?? 0;
    final other2 =
        double.tryParse(_otherDed2Controllers[guard.id]?.text ?? '0') ?? 0;
    final note = _overrideNoteControllers[guard.id]?.text;

    if (basic <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid Basic Salary')),
      );
      return;
    }

    final guardWithOverrides = guard.copyWith(
      isPfEnabled: _pfToggles[guard.id] ?? guard.isPfEnabled,
      isPtEnabled: _ptToggles[guard.id] ?? guard.isPtEnabled,
    );

    await ref
        .read(payrollProvider.notifier)
        .runPayrollForGuard(
          guard: guardWithOverrides,
          month: _selectedMonth.month,
          year: _selectedMonth.year,
          manualCalculationDays: calcDays,
          manualPresentDays: presentDays,
          manualOtDays: otDays,
          manualBasic: basic,
          manualOtBasic: otBasic,
          manualOtAmount: otAmount,
          overrideBy:
              SupabaseService().client.auth.currentUser?.email ?? 'Supervisor',
          overrideNote: note,
          canteenDeduction: canteen,
          penaltyDeduction: penalty,
          advanceDeduction: advance,
          uniformDeduction: uniform,
          otherDed1: other1,
          otherDed2: other2,
        );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Salary Slip generated for ${guard.fullName}')),
      );
    }
  }
}
