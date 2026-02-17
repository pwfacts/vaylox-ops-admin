import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/auth_service.dart';
import 'dart:async';

/// Supervisor app shell - Single unit roster board
/// Zero navigation complexity - everything on one screen
class SupervisorAppShell extends StatefulWidget {
  const SupervisorAppShell({super.key});

  @override
  State<SupervisorAppShell> createState() => _SupervisorAppShellState();
}

class _SupervisorAppShellState extends State<SupervisorAppShell> {
  final _supabase = Supabase.instance.client;

  String? _unitId;
  String? _unitName;
  List<Map<String, dynamic>> _guards = [];
  List<Map<String, dynamic>> _todayAttendance = [];
  bool _isLoading = true;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Auto-refresh every 30 seconds
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
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

      // Get the single unit this supervisor manages
      final unitResponse = await _supabase
          .from('field_officer_units')
          .select('unit_id, units(id, name)')
          .eq('user_id', userId)
          .single();

      _unitId = unitResponse['units']['id'];
      _unitName = unitResponse['units']['name'];

      // Get all guards assigned to this unit
      final guardsResponse = await _supabase.from('unit_assignments').select('''
            guard_id,
            guards(id, full_name, phone, status)
          ''').eq('unit_id', _unitId!).eq('status', 'active');

      _guards = (guardsResponse as List)
          .map((item) => {
                'id': item['guards']['id'],
                'name': item['guards']['full_name'],
                'phone': item['guards']['phone'],
                'status': item['guards']['status'],
              })
          .toList();

      // Get today's attendance for this unit
      final today = DateTime.now();
      final attendanceResponse = await _supabase
          .from('attendance')
          .select('''
            id,
            guard_id,
            shift,
            check_in_time,
            check_out_time,
            approval_status,
            verification_status
          ''')
          .eq('unit_id', _unitId!)
          .eq('attendance_date', today.toIso8601String().split('T')[0]);

      _todayAttendance =
          (attendanceResponse as List).cast<Map<String, dynamic>>();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Supervisor Dashboard',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (_unitName != null)
              Text(
                _unitName!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.grey[300],
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(),
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthService>().logout(),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildRosterBoard(),
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
            Text(
              'Error loading data',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

  Widget _buildRosterBoard() {
    return RefreshIndicator(
      onRefresh: () => _loadData(),
      child: CustomScrollView(
        slivers: [
          // Today's stats
          SliverToBoxAdapter(
            child: _buildStatsCard(),
          ),

          // Shift tabs
          SliverToBoxAdapter(
            child: _buildShiftTabs(),
          ),

          // Guard roster
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: _buildGuardList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    final present =
        _todayAttendance.where((a) => a['check_in_time'] != null).length;
    final total = _guards.length;
    final pending =
        _todayAttendance.where((a) => a['approval_status'] == 'PENDING').length;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              icon: Icons.people,
              label: 'Present',
              value: '$present/$total',
              color: Colors.green,
            ),
            Container(width: 1, height: 40, color: Colors.grey[300]),
            _buildStatItem(
              icon: Icons.pending_actions,
              label: 'Pending',
              value: pending.toString(),
              color: Colors.orange,
            ),
            Container(width: 1, height: 40, color: Colors.grey[300]),
            _buildStatItem(
              icon: Icons.check_circle_outline,
              label: 'Coverage',
              value: total > 0 ? '${(present / total * 100).round()}%' : '0%',
              color: Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildShiftTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildShiftChip('Day', true),
          const SizedBox(width: 8),
          _buildShiftChip('Night', false),
          const Spacer(),
          Text(
            DateTime.now().toString().split(' ')[0],
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftChip(String label, bool selected) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (value) {
        // TODO: Filter by shift
      },
    );
  }

  Widget _buildGuardList() {
    if (_guards.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: Text('No guards assigned to this unit'),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final guard = _guards[index];
          final attendance = _todayAttendance.firstWhere(
            (a) => a['guard_id'] == guard['id'],
            orElse: () => <String, dynamic>{},
          );

          return _buildGuardCard(guard, attendance);
        },
        childCount: _guards.length,
      ),
    );
  }

  Widget _buildGuardCard(
    Map<String, dynamic> guard,
    Map<String, dynamic> attendance,
  ) {
    final isPresent = attendance['check_in_time'] != null;
    final needsApproval = attendance['approval_status'] == 'PENDING';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isPresent ? Colors.green : Colors.grey[300],
                  child: Icon(
                    isPresent ? Icons.check : Icons.person,
                    color: isPresent ? Colors.white : Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guard['name'] ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isPresent && attendance['check_in_time'] != null)
                        Text(
                          'Check-in: ${_formatTime(attendance['check_in_time'])}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                if (!isPresent)
                  _buildQuickAction(
                    icon: Icons.add,
                    label: 'Mark Present',
                    color: Colors.green,
                    onTap: () => _markPresent(guard['id']),
                  ),
                if (isPresent && needsApproval)
                  _buildQuickAction(
                    icon: Icons.check_circle,
                    label: 'Approve',
                    color: Colors.blue,
                    onTap: () => _approveAttendance(attendance['id']),
                  ),
              ],
            ),
            if (isPresent && !needsApproval)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified, size: 16, color: Colors.green[700]),
                    const SizedBox(width: 6),
                    Text(
                      'Verified',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    final dateTime = DateTime.parse(isoString);
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _markPresent(String guardId) async {
    try {
      await _supabase.from('attendance').insert({
        'guard_id': guardId,
        'unit_id': _unitId,
        'attendance_date': DateTime.now().toIso8601String().split('T')[0],
        'shift': 'day', // TODO: Get from shift selector
        'check_in_time': DateTime.now().toUtc().toIso8601String(),
        'approval_status': 'PENDING',
        'assignment_type': 'MANUAL',
      });

      _loadData(silent: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked present successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _approveAttendance(String attendanceId) async {
    try {
      await _supabase.from('attendance').update({
        'approval_status': 'APPROVED',
        'approved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', attendanceId);

      _loadData(silent: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendance approved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}
