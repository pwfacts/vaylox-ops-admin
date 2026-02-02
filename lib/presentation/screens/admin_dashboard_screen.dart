import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../providers/dashboard_provider.dart';
import 'audit_log_screen.dart';
import 'unit_expense_screen.dart';
import 'system_settings_screen.dart';
import 'user_management_screen.dart';
import 'data_management_screen.dart';
import 'package:intl/intl.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Premium Dark
      appBar: AppBar(
        title: const Text('Executive Dashboard'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.blueAccent),
            tooltip: 'View System Audit Trail',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AuditLogScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey),
            tooltip: 'System Configuration',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SystemSettingsScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.people_outline, color: Colors.blueAccent),
            tooltip: 'Staff Management',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const UserManagementScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.archive_outlined,
              color: Colors.orangeAccent,
            ),
            tooltip: 'Data & Archives',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const DataManagementScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(dashboardStatsProvider),
          ),
        ],
      ),
      body: statsAsync.when(
        data: (stats) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardStatsProvider),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildSummaryGrid(context, stats),
              const SizedBox(height: 32),
              _buildChartsRow(stats),
              const SizedBox(height: 32),
              _buildAntiFraudSection(stats),
              const SizedBox(height: 32),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildSummaryGrid(BuildContext context, DashboardStats stats) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Total Guards',
          stats.totalGuards.toString(),
          Icons.people,
          Colors.blueAccent,
        ),
        _buildStatCard(
          'Active Units',
          stats.totalUnits.toString(),
          Icons.business,
          Colors.orangeAccent,
        ),
        _buildStatCard(
          'Today Coverage',
          '${stats.todayAttendancePercentage.toStringAsFixed(1)}%',
          Icons.fact_check,
          Colors.greenAccent,
        ),
        _buildStatCard(
          'Total Monthly Pay',
          '₹${NumberFormat.compact().format(stats.monthlyExpense)}',
          Icons.account_balance_wallet,
          Colors.purpleAccent,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const UnitExpenseScreen()),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withAlpha(26)),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(13),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Icon(icon, color: color, size: 20),
              ],
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartsRow(DashboardStats stats) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Guard Duty Distribution',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SfCircularChart(
              legend: Legend(
                isVisible: true,
                textStyle: const TextStyle(color: Colors.white),
              ),
              palette: const [Colors.blueAccent, Colors.orangeAccent],
              series: <CircularSeries>[
                DoughnutSeries<MapEntry<String, int>, String>(
                  dataSource: stats.attendanceTypeDistribution.entries.toList(),
                  xValueMapper: (MapEntry<String, int> data, _) => data.key,
                  yValueMapper: (MapEntry<String, int> data, _) => data.value,
                  dataLabelSettings: const DataLabelSettings(isVisible: true),
                  innerRadius: '60%',
                  explode: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAntiFraudSection(DashboardStats stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.security, color: Colors.redAccent, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Anti-Fraud Alerts',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const Spacer(),
            if (stats.fallbackAlerts.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withAlpha(51),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${stats.fallbackAlerts.length} High Risk',
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (stats.fallbackAlerts.isEmpty)
          const Card(
            color: Color(0xFF1E293B),
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.greenAccent),
                  SizedBox(width: 12),
                  Text(
                    'No suspicious activity detected this month.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else
          ...stats.fallbackAlerts.map((alert) => _buildAlertCard(alert)),
      ],
    );
  }

  Widget _buildAlertCard(ManualFallbackAlert alert) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withAlpha(51)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.redAccent.withAlpha(26),
            child: const Icon(Icons.warning, color: Colors.redAccent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.guardName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${alert.fallbackPercentage.toStringAsFixed(0)}% manual fallback in ${alert.totalDuties} duties',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }
}
