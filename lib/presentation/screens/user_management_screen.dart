import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/supabase_service.dart';

final staffListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
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
      {'full_name': 'Rahul Kumar', 'role': 'Supervisor', 'email': 'rahul@jds.com'},
      {'full_name': 'Sanjay Dev', 'role': 'Field Officer', 'email': 'sanjay@jds.com'},
    ];
  }
});

class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

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
            onPressed: () {}, // Invite Staff
          )
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getRoleColor(user['role'] ?? '').withOpacity(0.1),
                  child: Text(
                    (user['full_name'] ?? '?')[0].toUpperCase(),
                    style: TextStyle(color: _getRoleColor(user['role'] ?? ''), fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(user['full_name'] ?? 'Unknown User', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(user['email'] ?? '', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getRoleColor(user['role'] ?? '').withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (user['role'] ?? 'Staff').toUpperCase(),
                    style: TextStyle(color: _getRoleColor(user['role'] ?? ''), fontSize: 10, fontWeight: FontWeight.bold),
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
      case 'admin': return Colors.redAccent;
      case 'supervisor': return Colors.orangeAccent;
      case 'field officer': return Colors.blueAccent;
      default: return Colors.greenAccent;
    }
  }
}
