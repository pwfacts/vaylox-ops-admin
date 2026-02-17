import 'package:flutter/material.dart';
import '../../data/services/dashboard_service.dart';
import '../widgets/metric_card.dart';
import '../../core/auth/auth_service.dart';

class FieldOfficerDashboard extends StatefulWidget {
  const FieldOfficerDashboard({super.key});

  @override
  State<FieldOfficerDashboard> createState() => _FieldOfficerDashboardState();
}

class _FieldOfficerDashboardState extends State<FieldOfficerDashboard> {
  final DashboardService _service = DashboardService();
  bool _isLoading = true;
  Map<String, dynamic> _metrics = {};
  List<Map<String, dynamic>> _myUnits = [];
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
      final units = await _service.getMyUnits();

      if (mounted) {
        setState(() {
          _metrics = metrics;
          _myUnits = units;
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
        body: Center(child: Text('Error: $_error')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Officer Dashboard'),
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
              'Your Unit Status',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildMetricsGrid(),
            const SizedBox(height: 32),
            const Text(
              'My Units',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildUnitsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid() {
    // Reusing layout from Admin Dashboard but localized logic if needed
    // Copied for speed, should refactor to shared widget later
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
              title: 'My Guards',
              value: '${_metrics['total_guards'] ?? 0}',
              icon: Icons.shield,
              color: Colors.blue,
            ),
            MetricCard(
              title: 'Present',
              value: '${_metrics['present_today'] ?? 0}',
              icon: Icons.check_circle,
              color: Colors.green,
            ),
            MetricCard(
              title: 'Missing',
              value: '${_metrics['missing_today'] ?? 0}',
              icon: Icons.warning,
              color: Colors.red,
            ),
            MetricCard(
              title: 'Approvals',
              value: '${_metrics['pending_approvals'] ?? 0}',
              icon: Icons.pending_actions,
              color: Colors.orange,
            ),
          ],
        );
      },
    );
  }

  Widget _buildUnitsList() {
    if (_myUnits.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No units assigned to you.'),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _myUnits.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final unit = _myUnits[index];
        return Card(
          elevation: 0,
          color: const Color(0xFF1E293B),
          child: ListTile(
            leading: const Icon(Icons.business, color: Colors.blueAccent),
            title: Text(unit['name'] ?? 'Unnamed Unit'),
            subtitle: Text(unit['address'] ?? 'No address'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Navigate to unit details or scoped guard list
            },
          ),
        );
      },
    );
  }
}
