import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/payroll_providers.dart';

class PayrollGenerationScreen extends ConsumerStatefulWidget {
  const PayrollGenerationScreen({super.key});

  @override
  ConsumerState<PayrollGenerationScreen> createState() =>
      _PayrollGenerationScreenState();
}

class _PayrollGenerationScreenState
    extends ConsumerState<PayrollGenerationScreen> {
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Default to previous month if current date is early in the month (e.g. < 5th)
    if (DateTime.now().day < 5) {
      final prevMonth = DateTime.now().subtract(const Duration(days: 10));
      _selectedMonth = prevMonth.month;
      _selectedYear = prevMonth.year;
    }
  }

  Future<void> _generateDrafts() async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(payrollRepositoryProvider)
          .generatePayrollDrafts(_selectedMonth, _selectedYear);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Drafts generated successfully!')),
        );
        ref.invalidate(isPayrollLockedProvider(
            (month: _selectedMonth, year: _selectedYear)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _lockPayroll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Lock'),
        content: const Text(
            'Are you sure you want to LOCK the payroll? This action cannot be undone and will mark slips for payment.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Lock Payroll'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await ref
          .read(payrollRepositoryProvider)
          .lockPayroll(_selectedMonth, _selectedYear);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payroll LOCKED successfully!')),
        );
        ref.invalidate(isPayrollLockedProvider(
            (month: _selectedMonth, year: _selectedYear)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLockedAsync = ref.watch(
        isPayrollLockedProvider((month: _selectedMonth, year: _selectedYear)));

    return Scaffold(
      appBar: AppBar(title: const Text('Payroll Generation')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Period Selector
            Card(
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select Period',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _selectedMonth,
                            decoration:
                                const InputDecoration(labelText: 'Month'),
                            items: List.generate(12, (index) {
                              return DropdownMenuItem(
                                value: index + 1,
                                child: Text(_getMonthName(index + 1)),
                              );
                            }),
                            onChanged: (v) =>
                                setState(() => _selectedMonth = v!),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _selectedYear,
                            decoration:
                                const InputDecoration(labelText: 'Year'),
                            items: [2024, 2025, 2026, 2027].map((y) {
                              return DropdownMenuItem(
                                  value: y, child: Text('$y'));
                            }).toList(),
                            onChanged: (v) =>
                                setState(() => _selectedYear = v!),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Status & Actions
            isLockedAsync.when(
              data: (isLocked) {
                return Column(
                  children: [
                    if (isLocked)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          border: Border.all(color: Colors.green),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.lock, color: Colors.green, size: 48),
                            SizedBox(height: 8),
                            Text(
                              'Payroll is LOCKED',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green),
                            ),
                            Text('No further changes can be made.'),
                          ],
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          border: Border.all(color: Colors.orange),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.lock_open,
                                color: Colors.orange, size: 48),
                            SizedBox(height: 8),
                            Text(
                              'Payroll is OPEN',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange),
                            ),
                            Text('Drafts can be generated/regenerated.'),
                          ],
                        ),
                      ),
                    const SizedBox(height: 32),

                    // Action Buttons
                    if (!isLocked) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _generateDrafts,
                          icon: const Icon(Icons.refresh),
                          label: Text(_isLoading
                              ? 'Generating...'
                              : 'Generate / Regenerate Drafts'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.blue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _lockPayroll,
                          icon: const Icon(Icons.lock),
                          label: Text('Lock Payroll'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.red,
                          ),
                        ),
                      ),
                    ] else
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // Navigate to view slips or export
                          },
                          icon: const Icon(Icons.download),
                          label: const Text('Export Payroll Data'),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Error checking status: $e')),
            ),
          ],
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }
}
