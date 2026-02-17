import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/unit_providers.dart';

class FieldOfficerAssignmentDialog extends ConsumerStatefulWidget {
  final String unitId;
  const FieldOfficerAssignmentDialog({super.key, required this.unitId});

  @override
  ConsumerState<FieldOfficerAssignmentDialog> createState() =>
      _FieldOfficerAssignmentDialogState();
}

class _FieldOfficerAssignmentDialogState
    extends ConsumerState<FieldOfficerAssignmentDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _assignedFOs = [];
  List<Map<String, dynamic>> _availableFOs = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final repo = ref.read(unitRepositoryProvider);
    try {
      final assigned = await repo.getAssignedFieldOfficers(widget.unitId);
      final all = await repo.getAvailableFieldOfficers();

      final assignedIds = assigned.map((e) => e['user_id'] as String).toSet();
      final available =
          all.where((e) => !assignedIds.contains(e['id'])).toList();

      if (mounted) {
        setState(() {
          _assignedFOs = assigned;
          _availableFOs = available;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading FOs: $e')),
        );
      }
    }
  }

  Future<void> _assign(String userId) async {
    try {
      await ref
          .read(unitRepositoryProvider)
          .assignFieldOfficer(widget.unitId, userId);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error assigning: $e')),
      );
    }
  }

  Future<void> _unassign(String userId) async {
    try {
      await ref
          .read(unitRepositoryProvider)
          .removeFieldOfficer(widget.unitId, userId);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error removing: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(16),
        width: 400,
        height: 500,
        child: Column(
          children: [
            const Text(
              'Manage Field Officers',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView(
                  children: [
                    const Text('Assigned',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.blue)),
                    if (_assignedFOs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('No Field Officers assigned.'),
                      ),
                    ..._assignedFOs.map((fo) {
                      final user = fo['users'] ?? {}; // joined data
                      return ListTile(
                        leading: const Icon(Icons.person, color: Colors.green),
                        title: Text(user['full_name'] ?? 'Unknown'),
                        subtitle: Text(user['email'] ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.red),
                          onPressed: () => _unassign(fo['user_id']),
                        ),
                      );
                    }),
                    const Divider(),
                    const Text('Available',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.grey)),
                    if (_availableFOs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('No available Field Officers.'),
                      ),
                    ..._availableFOs.map((fo) {
                      return ListTile(
                        leading: const Icon(Icons.person_add_alt,
                            color: Colors.grey),
                        title: Text(fo['full_name'] ?? 'Unknown'),
                        subtitle: Text(fo['email'] ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.add_circle_outline,
                              color: Colors.blue),
                          onPressed: () => _assign(fo['id']),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
