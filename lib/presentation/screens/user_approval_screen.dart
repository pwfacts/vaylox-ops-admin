import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/access_profile_service.dart';

class UserApprovalScreen extends StatefulWidget {
  const UserApprovalScreen({super.key});

  @override
  State<UserApprovalScreen> createState() => _UserApprovalScreenState();
}

class _UserApprovalScreenState extends State<UserApprovalScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingUsers = [];

  @override
  void initState() {
    super.initState();
    _fetchPendingUsers();
  }

  Future<void> _fetchPendingUsers() async {
    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;
      final profile = await AccessProfileService().getAccessProfile();
      final orgId = profile.organizationId;

      if (orgId == null) {
        setState(() {
          _pendingUsers = [];
          _isLoading = false;
        });
        return;
      }

      // Fetch pending memberships for this org
      final response = await client
          .from('organization_users')
          .select('role, users(id, full_name, email, status, created_at)')
          .eq('organization_id', orgId)
          .eq('users.status', 'PENDING');

      final List<Map<String, dynamic>> results = [];
      for (var membership in List<Map<String, dynamic>>.from(response)) {
        final userData = membership['users'] as Map<String, dynamic>?;
        if (userData != null) {
          results.add({
            ...userData,
            'role': membership['role'],
          });
        }
      }

      if (mounted) {
        setState(() {
          _pendingUsers = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching users: $e')),
        );
      }
    }
  }

  Future<void> _approveUser(String userId, String name) async {
    try {
      await Supabase.instance.client
          .from('users')
          .update({'status': 'ACTIVE'}).eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name Approved')),
        );
        _fetchPendingUsers();
      }

      // Also ensure they are in the guards table if role is guard?
      // For now, simpler flow: Just activate user.
      // In a real app, you might want to create the Guard record here.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error approving: $e')),
        );
      }
    }
  }

  Future<void> _rejectUser(String userId) async {
    try {
      await Supabase.instance.client
          .from('users')
          .update({'status': 'REJECTED'}).eq('id', userId);

      if (mounted) {
        _fetchPendingUsers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error rejecting: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pending Approvals')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pendingUsers.isEmpty
              ? const Center(child: Text('No pending requests'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _pendingUsers.length,
                  itemBuilder: (context, index) {
                    final user = _pendingUsers[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            user['role'] == 'guard'
                                ? Icons.security
                                : Icons.person,
                          ),
                        ),
                        title: Text(user['full_name'] ?? 'Unknown'),
                        subtitle: Text(
                            '${user['email']} • ${user['role'].toString().toUpperCase()}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon:
                                  const Icon(Icons.check, color: Colors.green),
                              onPressed: () =>
                                  _approveUser(user['id'], user['full_name']),
                              tooltip: 'Approve',
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _rejectUser(user['id']),
                              tooltip: 'Reject',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
