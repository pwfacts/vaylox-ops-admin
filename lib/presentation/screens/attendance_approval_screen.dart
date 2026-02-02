import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/models/attendance_model.dart';
import '../../data/services/supabase_service.dart';
import '../providers/attendance_provider.dart';

class AttendanceApprovalScreen extends ConsumerStatefulWidget {
  final String unitId;

  const AttendanceApprovalScreen({super.key, required this.unitId});

  @override
  ConsumerState<AttendanceApprovalScreen> createState() =>
      _AttendanceApprovalScreenState();
}

class _AttendanceApprovalScreenState
    extends ConsumerState<AttendanceApprovalScreen> {
  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(pendingApprovalsProvider(widget.unitId));

    return Scaffold(
      appBar: AppBar(title: const Text('Pending Approvals')),
      body: pendingAsync.when(
        data: (list) => list.isEmpty
            ? const Center(child: Text('No pending approvals for this unit.'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = list[index];
                  return _buildApprovalCard(item);
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildApprovalCard(Attendance attendance) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (attendance.fallbackPhotoUrl != null)
            Image.network(
              attendance.fallbackPhotoUrl!,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.image_not_supported, size: 100),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guard ID: ${attendance.guardId}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Reason: ${attendance.fallbackReason?.name.replaceAll('_', ' ')}',
                ),
                if (attendance.fallbackReasonText != null)
                  Text(
                    'Note: ${attendance.fallbackReasonText}',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat(
                        'hh:mm a, dd MMM',
                      ).format(attendance.createdAt),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _handleAction(attendance.id, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _handleAction(attendance.id, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: const Text('Approve'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(String id, bool approve) async {
    try {
      final repo = ref.read(attendanceRepositoryProvider);
      final currentUserId = SupabaseService().currentUser!.id;

      if (approve) {
        await repo.approveAttendance(
          id,
          currentUserId,
          'Approved via mobile app',
        );
      } else {
        // Implement rejection if needed (status = 'REJECTED')
        await SupabaseService().client
            .from('attendance')
            .update({
              'approval_status': 'REJECTED',
              'approved_by': currentUserId,
              'approved_at': DateTime.now().toIso8601String(),
            })
            .eq('id', id);
      }

      ref.invalidate(pendingApprovalsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approve ? 'Approved' : 'Rejected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}

final pendingApprovalsProvider =
    FutureProvider.family<List<Attendance>, String>((ref, unitId) async {
      return ref.read(attendanceRepositoryProvider).getPendingApprovals(unitId);
    });
