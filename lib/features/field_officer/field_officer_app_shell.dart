import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/auth_service.dart';
import 'dart:async';

/// Field Officer app shell - Multi-unit monitoring
/// Grouped alerts and manual override capability
class FieldOfficerAppShell extends StatefulWidget {
  const FieldOfficerAppShell({super.key});

  @override
  State<FieldOfficerAppShell> createState() => _FieldOfficerAppShellState();
}

class _FieldOfficerAppShellState extends State<FieldOfficerAppShell> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _alerts = [];
  List<Map<String, dynamic>> _coverageTickets = [];
  bool _isLoading = true;
  String? _error;
  Timer? _refreshTimer;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Auto-refresh every 15 seconds
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _loadData(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final authService = context.read<AuthService>();
      final userId = authService.userId;

      if (userId == null) throw Exception('User not authenticated');

      // Get all units managed by this field officer
      final unitsResponse =
          await _supabase.from('field_officer_units').select('''
            unit_id,
            units(
              id,
              name,
              address,
              status,
              required_guards_day,
              required_guards_night
            )
          ''').eq('user_id', userId);

      _units = (unitsResponse as List)
          .map((item) => item['units'] as Map<String, dynamic>)
          .toList();

      // Get today's attendance stats for all units
      final today = DateTime.now().toIso8601String().split('T')[0];
      final unitIds = _units.map((u) => u['id']).toList();

      final attendanceResponse = await _supabase
          .from('attendance')
          .select('unit_id, guard_id, approval_status, shift')
          .eq('attendance_date', today)
          .inFilter('unit_id', unitIds);

      // Calculate stats for each unit
      for (var unit in _units) {
        final unitAttendance = (attendanceResponse as List)
            .where((a) => a['unit_id'] == unit['id'])
            .toList();

        unit['present_count'] = unitAttendance.length;
        unit['pending_approvals'] = unitAttendance
            .where((a) => a['approval_status'] == 'PENDING')
            .length;
        unit['required'] = unit['required_guards_day'] ?? 0;
        unit['shortage'] = (unit['required'] as int) - unitAttendance.length;
      }

      // Get active coverage tickets
      final ticketsResponse = await _supabase
          .from('coverage_tickets')
          .select('''
            id,
            unit_id,
            shift,
            shortage,
            status,
            created_at,
            current_wave,
            emergency_mode,
            units(name)
          ''')
          .inFilter('unit_id', unitIds)
          .inFilter('status', ['OPEN', 'EMERGENCY', 'MANUAL_REQUIRED'])
          .order('created_at', ascending: false);

      _coverageTickets = (ticketsResponse as List).cast<Map<String, dynamic>>();

      // Generate alerts
      _generateAlerts();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _generateAlerts() {
    _alerts = [];

    // Critical shortages
    for (var unit in _units) {
      final shortage = unit['shortage'] as int;
      if (shortage > 0) {
        _alerts.add({
          'type': 'SHORTAGE',
          'severity': shortage >= 2 ? 'CRITICAL' : 'WARNING',
          'unit_name': unit['name'],
          'unit_id': unit['id'],
          'message': 'Short $shortage guard(s)',
          'timestamp': DateTime.now(),
        });
      }
    }

    // Pending approvals
    for (var unit in _units) {
      final pending = unit['pending_approvals'] as int;
      if (pending > 0) {
        _alerts.add({
          'type': 'APPROVAL',
          'severity': 'INFO',
          'unit_name': unit['name'],
          'unit_id': unit['id'],
          'message': '$pending attendance(s) pending',
          'timestamp': DateTime.now(),
        });
      }
    }

    // Coverage tickets alerts
    for (var ticket in _coverageTickets) {
      String severity;
      String message;

      if (ticket['status'] == 'EMERGENCY') {
        severity = 'CRITICAL';
        message = 'Emergency mode active';
      } else if (ticket['status'] == 'MANUAL_REQUIRED') {
        severity = 'CRITICAL';
        message = 'Manual assignment required';
      } else {
        severity = 'WARNING';
        message = 'Wave ${ticket['current_wave'] ?? 1} sent';
      }

      _alerts.add({
        'type': 'COVERAGE',
        'severity': severity,
        'unit_name': ticket['units']['name'],
        'unit_id': ticket['unit_id'],
        'ticket_id': ticket['id'],
        'message': message,
        'timestamp': DateTime.parse(ticket['created_at']),
      });
    }

    // Sort by severity and time
    _alerts.sort((a, b) {
      final severityOrder = {'CRITICAL': 0, 'WARNING': 1, 'INFO': 2};
      final severityCompare = severityOrder[a['severity']]!
          .compareTo(severityOrder[b['severity']]!);

      if (severityCompare != 0) return severityCompare;

      return (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Field Officer Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthService>().logout(),
          ),
        ],
        bottom: TabBar(
          controller: null,
          tabs: const [
            Tab(text: 'Alerts', icon: Icon(Icons.notifications)),
            Tab(text: 'Units', icon: Icon(Icons.store)),
            Tab(text: 'Coverage', icon: Icon(Icons.warning)),
          ],
          onTap: (index) {
            setState(() {
              _selectedTabIndex = index;
            });
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Error loading data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _loadData(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: () => _loadData(),
      child: IndexedStack(
        index: _selectedTabIndex,
        children: [
          _buildAlertsTab(),
          _buildUnitsTab(),
          _buildCoverageTab(),
        ],
      ),
    );
  }

  Widget _buildAlertsTab() {
    if (_alerts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'All Clear',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text('No active alerts'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _alerts.length,
      itemBuilder: (context, index) {
        final alert = _alerts[index];
        return _buildAlertCard(alert);
      },
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    Color color;
    IconData icon;

    switch (alert['severity']) {
      case 'CRITICAL':
        color = Colors.red;
        icon = Icons.error;
        break;
      case 'WARNING':
        color = Colors.orange;
        icon = Icons.warning;
        break;
      default:
        color = Colors.blue;
        icon = Icons.info;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: color, size: 32),
        title: Text(
          alert['unit_name'],
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(alert['message']),
        trailing: alert['type'] == 'COVERAGE'
            ? TextButton(
                onPressed: () => _handleCoverageAlert(alert),
                child: const Text('Override'),
              )
            : null,
      ),
    );
  }

  Widget _buildUnitsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _units.length,
      itemBuilder: (context, index) {
        final unit = _units[index];
        return _buildUnitCard(unit);
      },
    );
  }

  Widget _buildUnitCard(Map<String, dynamic> unit) {
    final present = unit['present_count'] as int;
    final required = unit['required'] as int;
    final shortage = unit['shortage'] as int;
    final pending = unit['pending_approvals'] as int;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          // TODO: Navigate to unit details
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      unit['name'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (shortage > 0)
                    Chip(
                      label: Text('Short $shortage'),
                      backgroundColor: Colors.red[100],
                      labelStyle: TextStyle(color: Colors.red[700]),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildUnitStat('Present', '$present/$required', Colors.green),
                  const SizedBox(width: 24),
                  if (pending > 0)
                    _buildUnitStat(
                        'Pending', pending.toString(), Colors.orange),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnitStat(String label, String value, Color color) {
    return Row(
      children: [
        Icon(Icons.circle, size: 12, color: color),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCoverageTab() {
    if (_coverageTickets.isEmpty) {
      return const Center(
        child: Text('No active coverage tickets'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _coverageTickets.length,
      itemBuilder: (context, index) {
        final ticket = _coverageTickets[index];
        return _buildCoverageTicketCard(ticket);
      },
    );
  }

  Widget _buildCoverageTicketCard(Map<String, dynamic> ticket) {
    final isEmergency = ticket['emergency_mode'] == true;
    final needsManual = ticket['status'] == 'MANUAL_REQUIRED';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ticket['units']['name'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isEmergency || needsManual)
                  Chip(
                    label: Text(isEmergency ? 'EMERGENCY' : 'MANUAL'),
                    backgroundColor: Colors.red[100],
                    labelStyle: TextStyle(
                      color: Colors.red[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${ticket['shift']} shift - Short ${ticket['shortage']} guard(s)',
              style: TextStyle(color: Colors.grey[600]),
            ),
            if (!needsManual)
              Text(
                'Wave ${ticket['current_wave']} sent',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _viewTicketTimeline(ticket['id']),
                  child: const Text('View Timeline'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _manualOverride(ticket['id']),
                  child: const Text('Manual Override'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleCoverageAlert(Map<String, dynamic> alert) async {
    // Navigate to coverage ticket for manual override
    if (alert['ticket_id'] != null) {
      await _manualOverride(alert['ticket_id']);
    }
  }

  Future<void> _viewTicketTimeline(String ticketId) async {
    // TODO: Show timeline dialog with coverage_ticket_timeline view
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Coverage Timeline'),
        content: const Text('Timeline view coming soon'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _manualOverride(String ticketId) async {
    // TODO: Show guard selection dialog for manual assignment
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manual Override'),
        content: const Text('Guard selection coming soon'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
