import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../../data/services/supabase_service.dart';
import '../../core/auth/access_profile_service.dart';

final _logger = Logger();

final staffListProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final client = SupabaseService.client;
  try {
    // 1. Get current organization
    final profile = await AccessProfileService().getAccessProfile();
    final orgId = profile.organizationId;

    if (orgId == null) return [];

    // 2. Fetch staff memberships for this org
    final response = await client
        .from('organization_users')
        .select('role, users(id, full_name, email, status, created_at)')
        .eq('organization_id', orgId);

    final List<Map<String, dynamic>> results = [];
    for (var membership in List<Map<String, dynamic>>.from(response)) {
      final userData = membership['users'] as Map<String, dynamic>?;
      if (userData != null) {
        results.add({
          ...userData,
          'role': membership['role'], // Use the org-specific role
        });
      }
    }
    return results;
  } catch (e) {
    _logger.e('Error fetching users: $e');
    rethrow;
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
                  // Map display role to db role (e.g. Field Officer -> field_officer)
                  final dbRole =
                      selectedRole.toLowerCase().replaceAll(' ', '_');

                  // Get current user's organization ID
                  final profile =
                      await AccessProfileService().getAccessProfile();
                  final organizationId = profile.organizationId;

                  if (organizationId == null) {
                    throw Exception(
                        'You must be logged in to an organization to add users.');
                  }

                  // Note: In a real app, you'd use a service or edge function to create auth user
                  // This screen seems to assume the user already exists or is being invited.
                  // For now, mirroring the existing logic but splitting into two tables.

                  // 1. Create User Base Profile (Simplified for internal staff)
                  // In Supabase, usually auth.signUp triggers this, but we mirror existing manual insert
                  final userInsertRes = await client
                      .from('users')
                      .insert({
                        'full_name': nameController.text,
                        'email': emailController.text,
                        'status': 'active',
                      })
                      .select('id')
                      .single();

                  final newUserId = userInsertRes['id'];

                  // 2. Link to Organization
                  await client.from('organization_users').insert({
                    'user_id': newUserId,
                    'organization_id': organizationId,
                    'role': dbRole,
                    'email': emailController.text,
                  });

                  if (context.mounted) {
                    Navigator.pop(context);
                    ref.invalidate(staffListProvider);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Staff added successfully')),
                    );
                  }
                } catch (e) {
                  _logger.e('Error adding user: $e');
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
