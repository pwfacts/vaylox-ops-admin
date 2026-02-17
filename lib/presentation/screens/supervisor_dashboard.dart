import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_dashboard_screen.dart';
import 'supervisor_bulk_screen.dart';
import 'attendance_approval_screen.dart';
import 'payroll_wizard_screen.dart';

import 'package:logger/logger.dart';

final _logger = Logger();

class SupervisorDashboard extends StatelessWidget {
  const SupervisorDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchSupervisorUnit(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Supervisor Dashboard')),
            body: Center(
              child: Text(
                  'Error loading unit: ${snapshot.error ?? "No unit assigned"}'),
            ),
          );
        }

        final data = snapshot.data!;
        final unitId = data['unit_id'] as String?;
        final unitName = data['unit_name'] as String? ?? 'Assigned Unit';

        if (unitId == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Supervisor Dashboard')),
            body: const Center(
              child: Text('No Unit Assigned. Please contact Admin.'),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text('Dashboard - $unitName')),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildActionCard(
                context,
                title: 'Executive Analytics',
                subtitle: 'Overview of company performance',
                icon: Icons.analytics,
                color: Colors.blueAccent,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminDashboardScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildActionCard(
                context,
                title: 'Bulk Attendance',
                subtitle: 'Mark attendance for multiple guards',
                icon: Icons.group_add,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SupervisorBulkScreen(
                      unitId: unitId,
                      unitName: unitName,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildActionCard(
                context,
                title: 'Verify Fallbacks',
                subtitle: 'Review manual attendance requests',
                icon: Icons.verified_user,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AttendanceApprovalScreen(unitId: unitId),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildActionCard(
                context,
                title: 'Monthly Payroll',
                subtitle: 'Calculate and generate salary slips',
                icon: Icons.account_balance_wallet,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PayrollWizardScreen(
                      unitId: unitId,
                      unitName: unitName,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchSupervisorUnit(String userId) async {
    final client = Supabase.instance.client;
    // Attempt join first
    try {
      final res = await client
          .from('users')
          .select('unit_id, units:unit_id(name)')
          .eq('id', userId)
          .single();

      final unitId = res['unit_id'];
      final unitData = res['units'] as Map<String, dynamic>?;
      final unitName = unitData?['name'];

      return {'unit_id': unitId, 'unit_name': unitName};
    } catch (e) {
      _logger.w('Join failed, trying fallback or error: $e');
      // If join fails (FK issue?), try fetching unit_id only
      final res = await client
          .from('users')
          .select('unit_id')
          .eq('id', userId)
          .single();
      if (res['unit_id'] != null) {
        try {
          final unitRes = await client
              .from('units')
              .select('name')
              .eq('id', res['unit_id'])
              .single();
          return {'unit_id': res['unit_id'], 'unit_name': unitRes['name']};
        } catch (_) {
          return {'unit_id': res['unit_id'], 'unit_name': 'Unknown Unit'};
        }
      }
      throw Exception('User has no unit assigned');
    }
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.blueAccent,
  }) {
    return Card(
      elevation: 0,
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(20),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withAlpha(26), // ~0.1 opacity
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 28, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[400])),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
