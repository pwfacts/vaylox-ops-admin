import 'package:flutter/material.dart';
import '../../data/services/dashboard_service.dart';
import '../widgets/metric_card.dart';
import '../../core/auth/auth_service.dart';
import 'user_approval_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final DashboardService _service = DashboardService();
  bool _isLoading = true;
  Map<String, dynamic> _metrics = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _isLoading = true);

      final metrics = await _service.getOperationalMetrics();
      // final activity = await _service.getRecentActivity(); // Commented out until we handle joins/errors

      if (mounted) {
        setState(() {
          _metrics = metrics;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error loading dashboard: $_error'),
              ElevatedButton(
                onPressed: _loadData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operational Overview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Real-time Status',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildMetricsGrid(),
            const SizedBox(height: 32),
            const Text(
              'Recent Activity',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Placeholder for activity list until fully implemented
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Activity Log coming soon'),
                subtitle: Text('Audit logs will appear here'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 800 ? 4 : 2;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.5,
          children: [
            MetricCard(
              title: 'Total Guards',
              value: '${_metrics['total_guards'] ?? 0}',
              icon: Icons.shield,
              color: Colors.blue,
            ),
            MetricCard(
              title: 'Present Today',
              value: '${_metrics['present_today'] ?? 0}',
              icon: Icons.check_circle,
              color: Colors.green,
            ),
            MetricCard(
              title: 'Missing/Absent',
              value: '${_metrics['missing_today'] ?? 0}',
              icon: Icons.warning,
              color: Colors.red,
            ),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UserApprovalScreen()),
              ),
              child: MetricCard(
                title: 'Pending Approvals',
                value: '${_metrics['pending_approvals'] ?? 0}',
                icon: Icons.pending_actions,
                color: Colors.orange,
              ),
            ),
          ],
        );
      },
    );
  }
}
