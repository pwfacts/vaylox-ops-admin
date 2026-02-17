import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/supabase_service.dart';
import 'payroll_wizard_screen.dart';

final unitsListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = SupabaseService().client;
  final response = await client.from('units').select().order('created_at');
  return List<Map<String, dynamic>>.from(response);
});

class UnitManagementScreen extends ConsumerStatefulWidget {
  const UnitManagementScreen({super.key});

  @override
  ConsumerState<UnitManagementScreen> createState() =>
      _UnitManagementScreenState();
}

class _UnitManagementScreenState extends ConsumerState<UnitManagementScreen> {
  void _showUnitDialog({Map<String, dynamic>? unit}) {
    final nameController = TextEditingController(text: unit?['name']);
    final codeController = TextEditingController(text: unit?['code']);
    final addressController = TextEditingController(text: unit?['address']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(unit == null ? 'Add New Unit' : 'Edit Unit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Unit Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Unit Code (Prefix)',
                hintText: 'e.g., MALLA, SITE1',
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Address'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty || codeController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Name and Code are required')),
                );
                return;
              }

              final client = SupabaseService.client;
              try {
                if (unit == null) {
                  // Create
                  await client.from('units').insert({
                    'name': nameController.text,
                    'code': codeController.text.toUpperCase(),
                    'address': addressController.text,
                    'organization_id':
                        'c0a80101-b632-4e6a-9818-1d2f9d5e3f4b', // Default Company
                    'status': 'active',
                  });
                } else {
                  // Update
                  await client.from('units').update({
                    'name': nameController.text,
                    'code': codeController.text.toUpperCase(),
                    'address': addressController.text,
                  }).eq('id', unit['id']);
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  ref.invalidate(unitsListProvider);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unitsAsync = ref.watch(unitsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unit Management'),
      ),
      body: unitsAsync.when(
        data: (units) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: units.length,
          itemBuilder: (context, index) {
            final unit = units[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
                  child: Text(
                    (unit['code'] as String? ?? 'U').substring(0, 1),
                    style: const TextStyle(color: Colors.blueAccent),
                  ),
                ),
                title: Text(unit['name'] ?? 'Unnamed Unit'),
                subtitle: Text(
                    'Code: ${unit['code'] ?? '-'} | ${unit['address'] ?? ''}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.description, color: Colors.green),
                      tooltip: 'View/Export Attendance',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PayrollWizardScreen(
                              unitId: unit['id'],
                              unitName: unit['name'],
                            ),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _showUnitDialog(unit: unit),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Unit?'),
                            content: const Text(
                                'This will delete the unit. Guards assigned to this unit might be affected.'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete',
                                      style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          try {
                            await SupabaseService()
                                .client
                                .from('units')
                                .delete()
                                .eq('id', unit['id']);
                            ref.invalidate(unitsListProvider);
                          } catch (e) {
                            if (context.mounted) {
                              // mounted check
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')));
                            }
                          }
                        }
                      },
                    ),
                  ],
                ),
                onTap: () {
                  // Navigate to unit details or attendance?
                },
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUnitDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
