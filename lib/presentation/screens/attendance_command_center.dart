import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/attendance_providers.dart';
import '../../core/auth/auth_service.dart';

class AttendanceCommandCenterScreen extends ConsumerStatefulWidget {
  const AttendanceCommandCenterScreen({super.key});

  @override
  ConsumerState<AttendanceCommandCenterScreen> createState() =>
      _AttendanceCommandCenterScreenState();
}

class _AttendanceCommandCenterScreenState
    extends ConsumerState<AttendanceCommandCenterScreen> {
  String _date = DateTime.now().toIso8601String().split('T')[0];
  String _status = 'all';
  String? _unitId; // Can filter by unit if needed

  @override
  Widget build(BuildContext context) {
    final filter = AttendanceLogsFilter(
      date: _date,
      status: _status,
      unitId: _unitId,
    );
    final logsAsync = ref.watch(attendanceLogsProvider(filter));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Command Center'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ActionChip(
                  label: Text(_date),
                  avatar: const Icon(Icons.calendar_today, size: 16),
                  onPressed: _pickDate,
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _status,
                  underline: Container(),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Status')),
                    DropdownMenuItem(
                        value: 'PENDING_APPROVAL', child: Text('Pending')),
                    DropdownMenuItem(
                        value: 'APPROVED', child: Text('Approved')),
                    DropdownMenuItem(
                        value: 'REJECTED', child: Text('Rejected')),
                  ],
                  onChanged: (v) => setState(() => _status = v!),
                ),
              ],
            ),
          ),
        ),
      ),
      body: logsAsync.when(
        data: (logs) {
          if (logs.isEmpty) {
            return const Center(child: Text('No attendance records found.'));
          }
          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              final guard = log['guards'] ?? {};
              final unit = log['units'] ?? {};
              return _buildAttendanceCard(log, guard, unit);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildAttendanceCard(Map<String, dynamic> log,
      Map<String, dynamic> guard, Map<String, dynamic> unit) {
    final status = log['approval_status'] ?? 'PENDING';
    final time = log['check_in_time'] ?? 'Unknown';
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.help_outline;

    switch (status) {
      case 'APPROVED':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'REJECTED':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      case 'PENDING_APPROVAL':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1E293B),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      _getShiftColor(log['shift']).withValues(alpha: 0.2),
                  child: Text(
                    guard['full_name']?.substring(0, 1) ?? 'G',
                    style: const TextStyle(color: Colors.blue),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guard['full_name'] ?? 'Unknown Guard',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${unit['name'] ?? 'Unknown Unit'} • ${log['shift'] ?? 'Day'} Shift',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        Icon(statusIcon, color: statusColor, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          status,
                          style: TextStyle(color: statusColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            if (status == 'PENDING_APPROVAL') ...[
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => _updateStatus(log['id'], 'REJECTED'),
                    style:
                        OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Reject'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _updateStatus(log['id'], 'APPROVED'),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(String id, String newStatus) async {
    // Using a simpler way here since auth state is global
    try {
      final userId = AuthService().currentUser?.id;
      if (userId == null) return;

      await ref.read(attendanceRepositoryProvider).updateAttendanceStatus(
            attendanceId: id,
            status: newStatus,
            approverId: userId,
            notes: 'Manual action via Command Center',
          );

      // Refresh provider
      ref.invalidate(attendanceLogsProvider(AttendanceLogsFilter(
        date: _date,
        status: _status,
        unitId: _unitId,
      )));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_date),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _date = picked.toIso8601String().split('T')[0];
      });
    }
  }

  Color _getShiftColor(String? shift) {
    if (shift == 'Night') return Colors.indigo;
    if (shift == 'Day') return Colors.orange;
    return Colors.blue;
  }
}
