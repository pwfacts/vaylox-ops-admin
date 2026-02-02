import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/attendance_model.dart';
import '../../data/models/guard_model.dart';
import '../../data/services/supabase_service.dart';
import '../providers/attendance_provider.dart';
import '../widgets/animated_button.dart';

class SupervisorBulkScreen extends ConsumerStatefulWidget {
  final String unitId;
  final String unitName;

  const SupervisorBulkScreen({
    super.key,
    required this.unitId,
    required this.unitName,
  });

  @override
  ConsumerState<SupervisorBulkScreen> createState() =>
      _SupervisorBulkScreenState();
}

class _SupervisorBulkScreenState extends ConsumerState<SupervisorBulkScreen> {
  final List<String> _selectedGuardIds = [];
  bool _isProcessing = false;
  String? _selectedWorkedUnitId;

  @override
  Widget build(BuildContext context) {
    // We should fetch guards for THIS unit
    final guardsAsync = ref.watch(guardsByUnitProvider(widget.unitId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Bulk: ${widget.unitName}'),
        actions: [
          if (_selectedGuardIds.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _selectedGuardIds.clear()),
              child: const Text('Clear', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: guardsAsync.when(
        data: (guards) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _buildUnitSelector(),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: guards.length,
                itemBuilder: (context, index) {
                  final guard = guards[index];
                  final isSelected = _selectedGuardIds.contains(guard.id);

                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val!) {
                          _selectedGuardIds.add(guard.id);
                        } else {
                          _selectedGuardIds.remove(guard.id);
                        }
                      });
                    },
                    title: Text(guard.fullName),
                    subtitle: Text('Code: ${guard.guardCode}'),
                    secondary: CircleAvatar(
                      backgroundImage: guard.photoUrl != null
                          ? NetworkImage(guard.photoUrl!)
                          : null,
                      child: guard.photoUrl == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                  );
                },
              ),
            ),
            _buildBottomAction(guards),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildUnitSelector() {
    final unitsAsync = ref.watch(unitsProvider);
    _selectedWorkedUnitId ??= widget.unitId;

    return unitsAsync.when(
      data: (units) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Worked At Unit:',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(13),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withAlpha(26)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedWorkedUnitId,
                isExpanded: true,
                items: units
                    .map(
                      (u) => DropdownMenuItem(value: u.id, child: Text(u.name)),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedWorkedUnitId = val),
              ),
            ),
          ),
        ],
      ),
      loading: () => const LinearProgressIndicator(),
      error: (e, s) => Text('Error: $e'),
    );
  }

  Widget _buildBottomAction(List<Guard> allGuards) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(51),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_selectedGuardIds.length} Guards Selected',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_selectedGuardIds.length == allGuards.length) {
                      _selectedGuardIds.clear();
                    } else {
                      _selectedGuardIds.clear();
                      _selectedGuardIds.addAll(allGuards.map((g) => g.id));
                    }
                  });
                },
                child: Text(
                  _selectedGuardIds.length == allGuards.length
                      ? 'Deselect All'
                      : 'Select All',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedButton(
            text: 'Mark Bulk Attendance',
            isLoading: _isProcessing,
            onPressed: _selectedGuardIds.isEmpty ? () {} : _submitBulk,
          ),
        ],
      ),
    );
  }

  Future<void> _submitBulk() async {
    setState(() => _isProcessing = true);

    try {
      final repo = ref.read(attendanceRepositoryProvider);
      final currentUserId = SupabaseService().currentUser?.id;
      final now = DateTime.now();
      final hour = now.hour;
      final shift = (hour >= 8 && hour < 20) ? 'day' : 'night';

      for (var guardId in _selectedGuardIds) {
        // Find guard to get their primary unit
        final guards = await ref.read(
          guardsByUnitProvider(widget.unitId).future,
        );
        final guard = guards.firstWhere((g) => g.id == guardId);

        final isOt = _selectedWorkedUnitId != guard.assignedUnitId;

        final attendance = Attendance(
          id: const Uuid().v4(),
          companyId: defaultCompanyId,
          guardId: guardId,
          attendanceDate: now,
          shift: shift,
          unitId: _selectedWorkedUnitId!,
          workedUnitId: _selectedWorkedUnitId,
          primaryUnitId: guard.assignedUnitId,
          type: isOt ? AttendanceType.ot : AttendanceType.normal,
          attendanceMethod: AttendanceMethod.supervisor,
          approvalStatus: ApprovalStatus.approved,
          markedByUserId: currentUserId,
          createdAt: now,
          updatedAt: now,
        );

        await repo.markAttendance(attendance: attendance);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bulk attendance marked successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}
