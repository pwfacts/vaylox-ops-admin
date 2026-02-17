import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PayrollDashboard extends ConsumerWidget {
  const PayrollDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payroll Management')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_balance_wallet,
                size: 64, color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              'Payroll Command Center',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Authorized Personnel Only (Accountant/Admin)'),
            const SizedBox(height: 32),
            // Placeholder for payroll wizard navigation
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to payroll wizard (to be implemented)
              },
              icon: const Icon(Icons.payment),
              label: const Text('Process Monthly Payroll'),
            ),
          ],
        ),
      ),
    );
  }
}
