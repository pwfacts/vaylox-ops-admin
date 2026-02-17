import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/attendance_providers.dart';
import '../providers/payroll_providers.dart';

class ObservabilityDashboard extends ConsumerStatefulWidget {
  const ObservabilityDashboard({super.key});

  @override
  ConsumerState<ObservabilityDashboard> createState() =>
      _ObservabilityDashboardState();
}

class _ObservabilityDashboardState
    extends ConsumerState<ObservabilityDashboard> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System Observability')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildAttendanceSection(),
            const SizedBox(height: 24),
            _buildPayrollSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceSection() {
    return FutureBuilder<Map<String, dynamic>>(
      future: ref.read(attendanceRepositoryProvider).getAttendanceStats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();

        final stats = snapshot.data!;
        final total = stats['total'] as int;
        final manual = stats['manual'] as int;
        final rejected = stats['rejected'] as int;

        final manualRate = total > 0 ? (manual / total * 100) : 0.0;
        final isHighManual = manualRate > 20.0; // Threshold

        return Card(
          color: const Color(0xFF1E293B),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.security, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text('Attendance Integrity',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (isHighManual)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text('HIGH MANUAL RATE',
                            style: TextStyle(
                                color: Colors.red,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),
                _buildMetricRow('Total Logs (Month)', total.toString()),
                _buildMetricRow('Manual Overrides',
                    '$manual (${manualRate.toStringAsFixed(1)}%)',
                    color: isHighManual ? Colors.orange : Colors.white),
                _buildMetricRow('Rejections', rejected.toString(),
                    color: rejected > 0 ? Colors.red : Colors.green),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPayrollSection() {
    return FutureBuilder<Map<String, dynamic>>(
      future: ref.read(payrollRepositoryProvider).getPayrollStats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();

        final stats = snapshot.data!;
        final lockedMonths = stats['locked_months'] as int;
        final totalValue = stats['total_value'] as double;

        return Card(
          color: const Color(0xFF1E293B),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock_clock, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Financial Safety',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),
                _buildMetricRow('Locked Payrolls', '$lockedMonths / 12'),
                _buildMetricRow('Processed Value (YTD)',
                    '₹${totalValue.toStringAsFixed(2)}'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricRow(String label, String value,
      {Color color = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}
