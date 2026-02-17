import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/auth_service.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _companies = [];

  @override
  void initState() {
    super.initState();
    _fetchOrganizations();
  }

  Future<void> _fetchOrganizations() async {
    setState(() => _isLoading = true);
    try {
      // Fetch organizations and count their users via organization_users
      final response = await Supabase.instance.client
          .from('organizations')
          .select('*, organization_users(count)')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _companies = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching organizations: $e')),
        );
      }
    }
  }

  Future<void> _createOrganization() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Organization'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Organization Name'),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Address'),
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
              try {
                await Supabase.instance.client.from('organizations').insert({
                  'name': nameController.text.trim(),
                  'address': addressController.text.trim(),
                  'subscription_status': 'active',
                });
                if (context.mounted) {
                  Navigator.pop(context);
                  _fetchOrganizations();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error creating: $e')),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin Console'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _companies.length,
              itemBuilder: (context, index) {
                final company = _companies[index];
                // Supabase returns count differently depending on query
                // It might be {users: [{count: 5}]} or {users: {count: 5}} or just {users: []}
                int userCount = 0;
                final usersData = company['organization_users'];

                if (usersData is List && usersData.isNotEmpty) {
                  userCount = usersData.first['count'] ?? 0;
                } else if (usersData is Map) {
                  userCount = usersData['count'] ?? 0;
                }

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
                      child: Text(company['name'][0].toUpperCase()),
                    ),
                    title: Text(company['name']),
                    subtitle: Text(
                        '${company['subscription_status']} • $userCount Users'),
                    trailing: PopupMenuButton(
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                            value: 'edit', child: Text('Edit Details')),
                        const PopupMenuItem(
                            value: 'admin', child: Text('Create Admin')),
                        PopupMenuItem(
                          value: 'suspend',
                          child: Text(
                            company['subscription_status'] == 'ACTIVE'
                                ? 'Suspend'
                                : 'Activate',
                            style: TextStyle(
                                color:
                                    company['subscription_status'] == 'ACTIVE'
                                        ? Colors.red
                                        : Colors.green),
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        // Actions implemented below or TODO: Implement more actions
                        if (value == 'suspend') {
                          _toggleStatus(
                              company['id'], company['subscription_status']);
                        } else if (value == 'admin') {
                          _createTenantAdmin(company['id'], company['name']);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createOrganization,
        label: const Text('Add Organization'),
        icon: const Icon(Icons.add_business),
      ),
    );
  }

  Future<void> _createTenantAdmin(
      String organizationId, String companyName) async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('New Admin for $companyName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Warning: Creating a user will log you out of the admin session.',
              style: TextStyle(color: Colors.amber, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Admin Email'),
            ),
            TextField(
              controller: passwordController,
              decoration:
                  const InputDecoration(labelText: 'Temporary Password'),
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
              try {
                // 1. SignUp
                final response = await Supabase.instance.client.auth.signUp(
                  email: emailController.text.trim(),
                  password: passwordController.text.trim(),
                  data: {
                    'organization_id': organizationId,
                    'role': 'admin',
                    'status': 'ACTIVE',
                    'full_name': 'Admin',
                  },
                );

                if (response.user != null) {
                  // 2. Insert into users table
                  await Supabase.instance.client.from('users').insert({
                    'id': response.user!.id,
                    'email': emailController.text.trim(),
                    'full_name': 'Admin',
                    'status': 'ACTIVE',
                    'created_at': DateTime.now().toIso8601String(),
                  });

                  // 3. Insert into organization_users
                  await Supabase.instance.client
                      .from('organization_users')
                      .insert({
                    'user_id': response.user!.id,
                    'organization_id': organizationId,
                    'role': 'admin',
                    'email': emailController.text.trim(),
                  });

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Tenant Admin Created Successfully')),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Create Admin'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleStatus(String id, String currentStatus) async {
    final newStatus = currentStatus == 'active' ? 'suspended' : 'active';
    await Supabase.instance.client
        .from('organizations')
        .update({'subscription_status': newStatus}).eq('id', id);
    if (!mounted) return;
    _fetchOrganizations();
  }
}
