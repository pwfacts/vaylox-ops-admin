import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/salary_slip_model.dart';
import '../providers/payroll_provider.dart';
import '../providers/current_profile_provider.dart';

class SalarySlipListScreen extends ConsumerWidget {
  const SalarySlipListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Salary Slips')),
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) return const Center(child: Text('No profile found.'));
          
          final slipsAsync = ref.watch(guardSlipsProvider(profile.id));
          return slipsAsync.when(
            data: (slips) => slips.isEmpty
                ? const Center(child: Text('No salary slips available yet.'))
                : ListView.builder(
                    itemCount: slips.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final slip = slips[index];
                      return _buildSlipCard(context, slip);
                    },
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text('Error: $e')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildSlipCard(BuildContext context, SalarySlip slip) {
    final monthName = DateFormat('MMMM').format(DateTime(slip.year, slip.month));
    
    return Card(
      margin: const EdgeInsets.bottom(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text('$monthName ${slip.year}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Net Salary:'),
                Text('₹${slip.netPay.toStringAsFixed(2)}', 
                     style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Status: ${slip.status}', 
                 style: TextStyle(color: slip.status == 'PAID' ? AppColors.success : AppColors.warning)),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          // Navigate to detail
          _showSlipDetail(context, slip);
        },
      ),
    );
  }

  void _showSlipDetail(BuildContext context, SalarySlip slip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: AppColors.backgroundDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Salary Breakdown', style: AppTextStyles.heading2),
              const SizedBox(height: 24),
              
              _item('Basic Pay (Earned)', slip.basicPay),
              _item('Overtime Pay', slip.otPay),
              _item('Allowances', slip.otherAllowances),
              const Divider(height: 32),
              _item('Gross Earnings', slip.grossPay, isBold: true),
              
              const SizedBox(height: 24),
              const Text('Deductions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.error)),
              const SizedBox(height: 16),
              _item('Provident Fund (PF)', -slip.pfDeduction),
              _item('ESIC', -slip.esicDeduction),
              _item('Professional Tax', -slip.ptDeduction),
              _item('LWF', -slip.lwfDeduction),
              _item('Uniform', -slip.uniformDeduction),
              _item('Penalty', -slip.penaltyDeduction),
              _item('Canteen', -slip.canteenDeduction),
              _item('Advance Repayment', -slip.advanceDeduction),
              if (slip.otherDed1 > 0) _item('Other Ded 1', -slip.otherDed1),
              if (slip.otherDed2 > 0) _item('Other Ded 2', -slip.otherDed2),
              const Divider(height: 32),
              _item('Total Deductions', -slip.totalDeductions, isBold: true),
              
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('NET TAKE HOME', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('₹${slip.netPay.toStringAsFixed(2)}', 
                         style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.success)),
                  ],
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(String label, double value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(
            fontSize: 16, 
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: isBold ? Colors.white : Colors.grey[400],
          )),
          Text('₹${value.abs().toStringAsFixed(2)}', style: TextStyle(
            fontSize: 16, 
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: value < 0 ? AppColors.error : Colors.white,
          )),
        ],
      ),
    );
  }
}
