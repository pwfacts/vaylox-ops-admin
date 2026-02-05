import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../providers/dashboard_provider.dart';
import 'audit_log_screen.dart';
import 'unit_expense_screen.dart';
import 'system_settings_screen.dart';
import 'user_management_screen.dart';
import 'data_management_screen.dart';
import 'attendance_approval_screen.dart';
import 'package:intl/intl.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Light background
      body: Column(
        children: [
          _buildHeaderNavigation(context),
          Expanded(
            child: statsAsync.when(
              data: (stats) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(dashboardStatsProvider),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPageHeader(),
                      const SizedBox(height: 32),
                      _buildKPICards(context, stats),
                      const SizedBox(height: 32),
                      _buildChartsSection(stats),
                      const SizedBox(height: 32),
                      _buildAlertsSection(stats),
                    ],
                  ),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderNavigation(BuildContext context) {
    return Container(
      height: 70,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            // Logo and title
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.shield,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Guard Management',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 48),
            // Navigation items
            Expanded(
              child: Row(
                children: [
                  _buildNavItem('Dashboard', true),
                  _buildNavItem('Guards', false),
                  _buildNavItem('Attendance', false),
                  _buildNavItem('Salary', false),
                  _buildNavItem('Users', false),
                ],
              ),
            ),
            // Profile and settings
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () {},
                  color: const Color(0xFF6B7280),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () {},
                  color: const Color(0xFF6B7280),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(String title, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(right: 24),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFEFF6FF) : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getNavIcon(title),
            size: 16,
            color: isActive ? const Color(0xFF3B82F6) : const Color(0xFF6B7280),
          ),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
              color:
                  isActive ? const Color(0xFF3B82F6) : const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getNavIcon(String title) {
    switch (title) {
      case 'Dashboard':
        return Icons.dashboard_outlined;
      case 'Guards':
        return Icons.people_outline;
      case 'Attendance':
        return Icons.assignment_turned_in_outlined;
      case 'Salary':
        return Icons.account_balance_wallet_outlined;
      case 'Users':
        return Icons.group_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  Widget _buildPageHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dashboard',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Overview of security guard operations and key performance indicators',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildKPICards(BuildContext context, DashboardStats stats) {
    return Row(
      children: [
        Expanded(
          child: _buildKPICard(
            'Active Guards',
            '180',
            '+2%',
            true,
            Icons.people_outline,
            const Color(0xFF3B82F6),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildKPICard(
            'Attendance Rate',
            '98.5%',
            '+3%',
            true,
            Icons.trending_up_outlined,
            const Color(0xFF10B981),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildKPICard(
            'Monthly Billing',
            '₹5,20,000',
            '+5%',
            true,
            Icons.account_balance_wallet_outlined,
            const Color(0xFF8B5CF6),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildKPICard(
            'Pending Approvals',
            '12',
            null,
            null,
            Icons.access_time,
            const Color(0xFFF59E0B),
          ),
        ),
      ],
    );
  }

  Widget _buildKPICard(
    String title,
    String value,
    String? changeText,
    bool? isPositive,
    IconData icon,
    Color iconColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                ),
              ),
              Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          if (changeText != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  isPositive == true
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 14,
                  color: isPositive == true
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444),
                ),
                const SizedBox(width: 4),
                Text(
                  '$changeText vs last month',
                  style: TextStyle(
                    fontSize: 12,
                    color: isPositive == true
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKPICard(
    String title,
    String value,
    double? changeRate,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
    String? subtitle,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(26)),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(26),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                if (changeRate != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: changeRate >= 0
                          ? Colors.green.withAlpha(26)
                          : Colors.red.withAlpha(26),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${changeRate >= 0 ? '▲' : '▼'} ${changeRate.abs().toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: changeRate >= 0
                            ? Colors.greenAccent
                            : Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle ?? title,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (subtitle != null && changeRate == null)
              Text(
                'vs last month',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPendingApprovals(BuildContext context, DashboardStats stats) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pending Manual Approvals'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                '${stats.pendingApprovals} manual attendance entries require approval'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AttendanceApprovalScreen()),
                );
              },
              child: const Text('Review Pending Approvals'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
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

  Widget _buildChartsSection(DashboardStats stats) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: _buildAttendanceTrendChart(stats),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildUnitDistributionChart(stats),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildOTAnalysisChart(stats),
        ),
      ],
    );
  }

  Widget _buildAttendanceTrendChart(DashboardStats stats) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Attendance Trend',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Last 6 months attendance rate',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SfCartesianChart(
              plotAreaBorderWidth: 0,
              primaryXAxis: DateTimeAxis(
                majorGridLines: const MajorGridLines(width: 0),
                axisLabelFormatter: (AxisLabelRenderDetails details) {
                  final date = DateTime.fromMillisecondsSinceEpoch(
                      details.value.toInt());
                  return ChartAxisLabel(
                    DateFormat('MMM').format(date),
                    const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                  );
                },
              ),
              primaryYAxis: NumericAxis(
                majorGridLines:
                    const MajorGridLines(width: 0.5, color: Color(0xFFE5E7EB)),
                axisLabelFormatter: (AxisLabelRenderDetails details) {
                  return ChartAxisLabel(
                    '${details.value.toInt()}',
                    const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                  );
                },
                minimum: 50,
                maximum: 100,
                interval: 25,
              ),
              series: <ChartSeries>[
                LineSeries<AttendanceTrendData, DateTime>(
                  dataSource: stats.attendanceTrend,
                  xValueMapper: (AttendanceTrendData data, _) => data.date,
                  yValueMapper: (AttendanceTrendData data, _) =>
                      data.attendanceRate,
                  color: const Color(0xFF3B82F6),
                  width: 2,
                  markerSettings: const MarkerSettings(
                    isVisible: true,
                    color: Color(0xFF3B82F6),
                    borderColor: Colors.white,
                    borderWidth: 2,
                    height: 6,
                    width: 6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitDistributionChart(DashboardStats stats) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Unit Distribution',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Guards per unit',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SfCircularChart(
              legend: Legend(
                isVisible: true,
                position: LegendPosition.bottom,
                textStyle:
                    const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
              ),
              palette: const [
                Color(0xFF3B82F6),
                Color(0xFF10B981),
                Color(0xFFF59E0B),
                Color(0xFFEF4444),
                Color(0xFF8B5CF6),
              ],
              series: <CircularSeries>[
                PieSeries<UnitDistributionData, String>(
                  dataSource: stats.unitDistribution.take(5).toList(),
                  xValueMapper: (UnitDistributionData data, _) =>
                      data.unitName.length > 8
                          ? '${data.unitName.substring(0, 8)}...'
                          : data.unitName,
                  yValueMapper: (UnitDistributionData data, _) =>
                      data.guardCount,
                  dataLabelSettings: const DataLabelSettings(
                    isVisible: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOTAnalysisChart(DashboardStats stats) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OT Analysis',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Overtime hours by unit',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SfCartesianChart(
              plotAreaBorderWidth: 0,
              primaryXAxis: CategoryAxis(
                majorGridLines: const MajorGridLines(width: 0),
                axisLabelFormatter: (AxisLabelRenderDetails details) {
                  return ChartAxisLabel(
                    details.text.length > 6
                        ? '${details.text.substring(0, 6)}...'
                        : details.text,
                    const TextStyle(color: Color(0xFF6B7280), fontSize: 10),
                  );
                },
              ),
              primaryYAxis: NumericAxis(
                majorGridLines:
                    const MajorGridLines(width: 0.5, color: Color(0xFFE5E7EB)),
                axisLabelFormatter: (AxisLabelRenderDetails details) {
                  return ChartAxisLabel(
                    details.value.toInt().toString(),
                    const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                  );
                },
              ),
              legend: Legend(
                isVisible: true,
                position: LegendPosition.bottom,
                textStyle:
                    const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
              ),
              series: <ChartSeries>[
                ColumnSeries<OtAnalysisData, String>(
                  name: 'OT Hours',
                  dataSource: stats.otAnalysis.take(4).toList(),
                  xValueMapper: (OtAnalysisData data, _) => data.unitName,
                  yValueMapper: (OtAnalysisData data, _) => data.otHours,
                  color: const Color(0xFF10B981),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceTrendChart(DashboardStats stats) {
    return Container(
      height: 280,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent.withAlpha(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Attendance Trend (6 Months)',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SfCartesianChart(
              primaryXAxis: DateTimeAxis(
                majorGridLines: const MajorGridLines(width: 0),
                axisLabelFormatter: (AxisLabelRenderDetails details) {
                  final date = DateTime.fromMillisecondsSinceEpoch(
                      details.value.toInt());
                  return ChartAxisLabel(
                    DateFormat('MMM').format(date),
                    const TextStyle(color: Colors.grey, fontSize: 12),
                  );
                },
              ),
              primaryYAxis: NumericAxis(
                majorGridLines:
                    const MajorGridLines(width: 0.5, color: Colors.grey),
                axisLabelFormatter: (AxisLabelRenderDetails details) {
                  return ChartAxisLabel(
                    '${details.value.toInt()}%',
                    const TextStyle(color: Colors.grey, fontSize: 12),
                  );
                },
              ),
              plotAreaBorderWidth: 0,
              series: <ChartSeries>[
                LineSeries<AttendanceTrendData, DateTime>(
                  dataSource: stats.attendanceTrend,
                  xValueMapper: (AttendanceTrendData data, _) => data.date,
                  yValueMapper: (AttendanceTrendData data, _) =>
                      data.attendanceRate,
                  color: Colors.blueAccent,
                  width: 3,
                  markerSettings: const MarkerSettings(
                    isVisible: true,
                    color: Colors.blueAccent,
                    borderColor: Colors.white,
                    borderWidth: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitDistributionChart(DashboardStats stats) {
    return Container(
      height: 280,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orangeAccent.withAlpha(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart, color: Colors.orangeAccent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Unit Distribution',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SfCircularChart(
              legend: Legend(
                isVisible: true,
                textStyle: const TextStyle(color: Colors.white70, fontSize: 10),
                position: LegendPosition.bottom,
              ),
              series: <CircularSeries>[
                DoughnutSeries<UnitDistributionData, String>(
                  dataSource:
                      stats.unitDistribution.take(5).toList(), // Top 5 units
                  xValueMapper: (UnitDistributionData data, _) =>
                      data.unitName.length > 10
                          ? '${data.unitName.substring(0, 10)}...'
                          : data.unitName,
                  yValueMapper: (UnitDistributionData data, _) =>
                      data.guardCount,
                  dataLabelSettings: const DataLabelSettings(
                    isVisible: true,
                    textStyle: TextStyle(fontSize: 8),
                  ),
                  innerRadius: '50%',
                  explode: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtAnalysisChart(DashboardStats stats) {
    return Container(
      height: 280,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.greenAccent.withAlpha(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, color: Colors.greenAccent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'OT Analysis by Unit',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SfCartesianChart(
              primaryXAxis: CategoryAxis(
                majorGridLines: const MajorGridLines(width: 0),
                axisLabelFormatter: (AxisLabelRenderDetails details) {
                  final text = details.text;
                  return ChartAxisLabel(
                    text.length > 8 ? '${text.substring(0, 8)}...' : text,
                    const TextStyle(color: Colors.grey, fontSize: 10),
                  );
                },
              ),
              primaryYAxis: NumericAxis(
                majorGridLines:
                    const MajorGridLines(width: 0.5, color: Colors.grey),
                axisLabelFormatter: (AxisLabelRenderDetails details) {
                  return ChartAxisLabel(
                    '${details.value.toInt()}h',
                    const TextStyle(color: Colors.grey, fontSize: 12),
                  );
                },
              ),
              plotAreaBorderWidth: 0,
              series: <ChartSeries>[
                ColumnSeries<OtAnalysisData, String>(
                  name: 'Normal Hours',
                  dataSource: stats.otAnalysis,
                  xValueMapper: (OtAnalysisData data, _) => data.unitName,
                  yValueMapper: (OtAnalysisData data, _) => data.normalHours,
                  color: Colors.blueAccent,
                ),
                ColumnSeries<OtAnalysisData, String>(
                  name: 'OT Hours',
                  dataSource: stats.otAnalysis,
                  xValueMapper: (OtAnalysisData data, _) => data.unitName,
                  yValueMapper: (OtAnalysisData data, _) => data.otHours,
                  color: Colors.orangeAccent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualFallbackChart(DashboardStats stats) {
    return Container(
      height: 280,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withAlpha(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning, color: Colors.redAccent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Manual Fallback Alerts',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: stats.fallbackAlerts.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 48),
                        SizedBox(height: 8),
                        Text(
                          'No High-Risk Guards',
                          style: TextStyle(
                              color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'All guards below 30% fallback threshold',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: stats.fallbackAlerts.length,
                    itemBuilder: (context, index) {
                      final alert = stats.fallbackAlerts[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(26),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withAlpha(51)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person,
                                color: Colors.redAccent, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    alert.guardName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${alert.fallbackPercentage.toStringAsFixed(1)}% fallback (${alert.totalDuties} duties)',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'HIGH',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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

  Widget _buildFinancialPivotSection(DashboardStats stats) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purpleAccent.withAlpha(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.table_chart,
                  color: Colors.purpleAccent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Financial Pivot Table',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _exportFinancialData(stats),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Export to Excel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            height: 300,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowColor: MaterialStateProperty.all(Colors.grey[900]),
                  dataRowColor:
                      MaterialStateProperty.all(const Color(0xFF0F172A)),
                  columns: const [
                    DataColumn(
                        label: Text('Area',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Unit',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Guards',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Monthly Billing',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Deductions',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Net Pay',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Status',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))),
                  ],
                  rows: _buildFinancialRows(stats),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info, color: Colors.blueAccent, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'Interactive drill-down: Group by Area > Unit > Guard | Values: Billing, Deductions, Net Pay, Payment Status',
                  style: TextStyle(color: Colors.blue, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<DataRow> _buildFinancialRows(DashboardStats stats) {
    final rows = <DataRow>[];

    for (int i = 0; i < stats.unitDistribution.length && i < 6; i++) {
      final unit = stats.unitDistribution[i];
      final billing = (unit.guardCount * 15000 * (0.8 + i * 0.05))
          .round(); // Mock calculation
      final deductions = (billing * 0.12).round(); // 12% deductions
      final netPay = billing - deductions;
      final status = i % 3 == 0 ? 'Pending' : 'Paid';

      rows.add(DataRow(
        cells: [
          DataCell(
              Text(unit.areaName, style: const TextStyle(color: Colors.white))),
          DataCell(
              Text(unit.unitName, style: const TextStyle(color: Colors.white))),
          DataCell(Text('${unit.guardCount}',
              style: const TextStyle(color: Colors.white))),
          DataCell(Text('₹${NumberFormat.compact().format(billing)}',
              style: const TextStyle(color: Colors.white))),
          DataCell(Text('₹${NumberFormat.compact().format(deductions)}',
              style: const TextStyle(color: Colors.red))),
          DataCell(Text('₹${NumberFormat.compact().format(netPay)}',
              style: const TextStyle(color: Colors.green))),
          DataCell(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: status == 'Paid'
                    ? Colors.green.withAlpha(26)
                    : Colors.orange.withAlpha(26),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: status == 'Paid'
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ));
    }

    return rows;
  }

  Widget _buildAlertsSection(DashboardStats stats) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Alerts & Notifications',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.notifications_outlined,
                color: Colors.grey[600],
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildAlertItem(
            '12 Pending Approvals',
            'Manual attendance records require supervisor review',
            const Color(0xFFEF4444),
            Icons.error_outline,
          ),
          const SizedBox(height: 16),
          _buildAlertItem(
            'Salary Processing Due',
            'January 2026 salary processing scheduled for Feb 1st',
            const Color(0xFF10B981),
            Icons.check_circle_outline,
          ),
          const SizedBox(height: 16),
          _buildAlertItem(
            'Manual Fallback Alert',
            'Guard BH001 has exceeded 30% manual fallback threshold',
            const Color(0xFFF59E0B),
            Icons.warning_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildAlertItem(
      String title, String description, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: color, width: 4),
        ),
        color: color.withOpacity(0.05),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
