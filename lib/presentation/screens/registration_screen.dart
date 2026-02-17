import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/auth_text_field.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  // State
  bool _isLoading = false;
  List<Map<String, dynamic>> _organizations = [];
  String? _selectedOrganizationId;
  String _selectedRole = 'guard'; // Default role

  @override
  void initState() {
    super.initState();
    _fetchOrganizations();
  }

  Future<void> _fetchOrganizations() async {
    try {
      final response = await Supabase.instance.client
          .from('organizations')
          .select('id, name')
          .eq('subscription_status', 'active')
          .order('name');

      if (mounted) {
        setState(() {
          _organizations = List<Map<String, dynamic>>.from(response);
          if (_organizations.isNotEmpty) {
            _selectedOrganizationId = _organizations.first['id'];
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load organizations: $e')),
        );
      }
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedOrganizationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an organization')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final name = _nameController.text.trim();

      // 1. SignUp
      final authResponse = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': name,
          'organization_id': _selectedOrganizationId,
          'role': _selectedRole,
          'status': 'PENDING', // Explicitly set pending
        },
      );

      final userId = authResponse.user?.id;
      if (userId == null) throw Exception('Registration failed');

      // 2. Create User Profile
      await Supabase.instance.client.from('users').insert({
        'id': userId,
        'email': email,
        'full_name': name,
        'status': 'PENDING',
        'created_at': DateTime.now().toIso8601String(),
      });

      // 3. Create Organization Membership
      await Supabase.instance.client.from('organization_users').insert({
        'user_id': userId,
        'organization_id': _selectedOrganizationId,
        'email': email,
        'role': _selectedRole,
      });

      if (mounted) {
        // Show success dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Registration Successful'),
            content: const Text(
              'Your account has been created and is pending approval from the organization admin.\n\nPlease contact your supervisor to activate your account.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(context).pop(); // Back to login
                },
                child: const Text('Back to Login'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Error: ${e.toString().contains('already registered') ? 'Email already in use' : e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Organization')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Create Account',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Organization Dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedOrganizationId,
                    decoration: const InputDecoration(
                      labelText: 'Select Organization',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business),
                    ),
                    items: _organizations.map((org) {
                      return DropdownMenuItem<String>(
                        value: org['id'],
                        child: Text(org['name']),
                      );
                    }).toList(),
                    onChanged: (val) =>
                        setState(() => _selectedOrganizationId = val),
                    validator: (val) => val == null ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),

                  // Role Selection
                  DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'I am a...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'guard', child: Text('Security Guard')),
                      DropdownMenuItem(
                          value: 'field_officer', child: Text('Field Officer')),
                      DropdownMenuItem(
                          value: 'supervisor', child: Text('Supervisor')),
                    ],
                    onChanged: (val) => setState(() => _selectedRole = val!),
                  ),
                  const SizedBox(height: 16),

                  AuthTextField(
                    controller: _nameController,
                    label: 'Full Name',
                    icon: Icons.person,
                    validator: (v) => v?.isEmpty == true ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),

                  AuthTextField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email,
                    validator: (v) =>
                        v?.contains('@') == true ? null : 'Invalid email',
                  ),
                  const SizedBox(height: 16),

                  AuthTextField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock,
                    isPassword: true,
                    validator: (v) =>
                        (v?.length ?? 0) < 6 ? 'Min 6 chars' : null,
                  ),
                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Register'),
                  ),

                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Already have an account? Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
