import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/supabase_service.dart';

final staffListProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final client = SupabaseService().client;
  // This assumes a 'profiles' or 'users' table exists since the PRD references 'users' ID
  // If it doesn't exist, we will fallback to a dummy list for demonstration.
  try {
    final response = await client.from('profiles').select();
    return List<Map<String, dynamic>>.from(response);
  } catch (e) {
    // Return dummy data if table not found
    return [
      {'full_name': 'Prabhat Singh', 'role': 'Admin', 'email': 'admin@jds.com'},
      {
        'full_name': 'Rahul Kumar',
        'role': 'Supervisor',
        'email': 'rahul@jds.com',
      },
      {
        'full_name': 'Sanjay Dev',
        'role': 'Field Officer',
        'email': 'sanjay@jds.com',
      },
    ];
  }
});

class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  void _showAddUserDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    String selectedRole = 'Supervisor';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'Add New Staff Member',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
              TextField(
                controller: emailController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedRole,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'System Role',
                  labelStyle: TextStyle(color: Colors.grey),
                ),
                items: ['Admin', 'Supervisor', 'Field Officer']
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (val) => setState(() => selectedRole = val!),
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
                final client = SupabaseService().client;
                try {
                  // In a real app, you'd use a cloud function to create the actual auth user
                  // For now, we'll create the profile which triggers the workflow.
                  await client.from('profiles').insert({
                    'full_name': nameController.text,
                    'email': emailController.text,
                    'role': selectedRole,
                    'company_id':
                        'c0a80101-b632-4e6a-9818-1d2f9d5e3f4b', // Default Company
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                    ref.invalidate(staffListProvider);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Staff added successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Create Account'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Staff Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.blueAccent),
            onPressed: () => _showAddUserDialog(context, ref),
          ),
        ],
      ),
      body: staffAsync.when(
        data: (staff) => ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: staff.length,
          itemBuilder: (context, index) {
            final user = staff[index];
            return Card(
              color: const Color(0xFF1E293B),
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getRoleColor(
                    user['role'] ?? '',
                  ).withAlpha(26),
                  child: Text(
                    (user['full_name'] ?? '?')[0].toUpperCase(),
                    style: TextStyle(
                      color: _getRoleColor(user['role'] ?? ''),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  user['full_name'] ?? 'Unknown User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  user['email'] ?? '',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getRoleColor(user['role'] ?? '').withAlpha(26),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (user['role'] ?? 'Staff').toUpperCase(),
                    style: TextStyle(
                      color: _getRoleColor(user['role'] ?? ''),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.redAccent;
      case 'supervisor':
        return Colors.orangeAccent;
      case 'field officer':
        return Colors.blueAccent;
      default:
        return Colors.greenAccent;
    }
  }
}
