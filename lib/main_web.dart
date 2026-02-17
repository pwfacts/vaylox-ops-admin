import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'presentation/screens/admin_dashboard_screen.dart';
import 'presentation/screens/payroll_wizard_screen.dart';
import 'presentation/screens/guard_list_screen.dart';
import 'presentation/screens/supervisor_bulk_screen.dart';
import 'presentation/screens/attendance_approval_screen.dart';
import 'presentation/screens/user_management_screen.dart';
import 'presentation/screens/super_admin_dashboard.dart';
import 'presentation/screens/unit_management_screen.dart';
import 'core/auth/access_profile.dart';
import 'core/auth/access_profile_service.dart';
import 'presentation/screens/supervisor_dashboard.dart';
import 'presentation/screens/field_officer_dashboard.dart';
import 'presentation/screens/payroll_dashboard.dart';

import 'package:logger/logger.dart';

final _logger = Logger();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const ProviderScope(child: VayloxOpsWebAdmin()));
}

class VayloxOpsWebAdmin extends StatelessWidget {
  const VayloxOpsWebAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vaylox Ops - Admin Portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.dark,
          surface: const Color(0xFF111827),
        ),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      home: const InitializationWrapper(),
    );
  }
}

class InitializationWrapper extends StatefulWidget {
  const InitializationWrapper({super.key});

  @override
  State<InitializationWrapper> createState() => _InitializationWrapperState();
}

class _InitializationWrapperState extends State<InitializationWrapper> {
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await _doInitialization();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
        });
      }
    } catch (e) {
      _logger.e('Initialization error: $e');
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _doInitialization() async {
    // Use 'const' for dart-define to work properly at build time
    const envUrl = String.fromEnvironment('VITE_SUPABASE_URL');
    const envKey = String.fromEnvironment('VITE_SUPABASE_ANON_KEY');

    _logger.i('Environment URL: $envUrl');
    _logger.i('Environment Key: ${envKey.isNotEmpty ? 'PRESENT' : 'MISSING'}');

    if (envUrl.isNotEmpty && envKey.isNotEmpty) {
      // print('Using environment variables for Supabase initialization'); // Phase 8: Structured logging preferred
      await Supabase.initialize(
        url: envUrl,
        anonKey: envKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
    } else {
      throw Exception(
          'CRITICAL: Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY. Cannot start in production mode.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'Failed to initialize app',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _errorMessage = '';
                  });
                  _initializeApp();
                },
                child: const Text('Retry'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Force reload of the web app
                  // html.window.location.reload(); // Not available in pure Dart/Flutter without import
                  // For now just retry
                  setState(() {
                    _hasError = false;
                    _errorMessage = '';
                  });
                  _initializeApp();
                },
                child: const Text('Reload Application'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  color: Color(0xFF2563EB),
                ),
                SizedBox(height: 24),
                Text(
                  'Initializing Vaylox Ops...',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const WebAuthWrapper();
  }
}

class WebAuthWrapper extends StatelessWidget {
  const WebAuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data?.session != null) {
          return const RoleCheckWrapper();
        }
        return const WebLoginScreen();
      },
    );
  }
}

class RoleCheckWrapper extends StatelessWidget {
  const RoleCheckWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AccessProfile>(
      future: AccessProfileService().getAccessProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.gpp_bad,
                          size: 64, color: Colors.redAccent),
                      const SizedBox(height: 24),
                      const Text(
                        'Access Denied',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text('Return to Login'),
                          onPressed: () =>
                              Supabase.instance.client.auth.signOut(),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(20),
                            backgroundColor: Colors.white10,
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final profile = snapshot.data;
        if (profile == null) return const SizedBox();

        if (profile.isPlatformAdmin) {
          return const SuperAdminDashboardScreen();
        }

        // Strict Role Routing - Task 2
        switch (profile.role) {
          case 'admin':
            return const WebAdminHome();
          case 'field_officer':
            return const FieldOfficerDashboard();
          case 'supervisor':
            return const SupervisorDashboard();
          case 'accountant':
            return const PayrollDashboard();
          default:
            // Fail Closed
            return Scaffold(
                body: Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                  const Text("Unauthorized Role"),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Supabase.instance.client.auth.signOut(),
                    child: const Text('Logout'),
                  )
                ])));
        }
      },
    );
  }
}

class WebLoginScreen extends StatefulWidget {
  const WebLoginScreen({super.key});

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  // _bypassLogin removed for production security

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      _logger.i('Attempting login with email: ${_emailController.text.trim()}');
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      _logger.i(
          'Login response: ${response.session != null ? 'Success' : 'Failed'}');
    } catch (e) {
      _logger.e('Login error details: $e');
      if (mounted) {
        String errorMessage = 'Login failed';
        if (e.toString().contains('Invalid login credentials')) {
          errorMessage = 'Invalid email or password';
        } else if (e.toString().contains('Email not confirmed')) {
          errorMessage = 'Please confirm your email first';
        } else if (e.toString().contains('400')) {
          errorMessage = 'Invalid request. Check email format.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$errorMessage\nDetails: $e'),
            duration: const Duration(seconds: 5),
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.admin_panel_settings,
                      size: 64,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Vaylox Ops',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Admin Portal',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                      obscureText: true,
                      onSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          backgroundColor: Colors.blueAccent,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Sign In',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const SizedBox(height: 24),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock, size: 14, color: Colors.grey),
                        SizedBox(width: 8),
                        Text(
                          'Authorized Personnel Only',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Skip Login button removed
                    const SizedBox(height: 16),
                    // Test Credentials container removed
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WebAdminHome extends StatelessWidget {
  const WebAdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vaylox Ops - Admin Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: GridView.count(
        crossAxisCount: 3,
        padding: const EdgeInsets.all(24),
        children: [
          _buildCard(
            context,
            'Executive Dashboard',
            Icons.dashboard,
            Colors.blueAccent,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
            ),
          ),
          _buildCard(
            context,
            'Payroll Wizard',
            Icons.payments,
            Colors.greenAccent,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PayrollWizardScreen(
                  unitId: 'all',
                  unitName: 'All Units',
                ),
              ),
            ),
          ),
          _buildCard(
            context,
            'Site / Unit Management',
            Icons.domain,
            Colors.tealAccent,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UnitManagementScreen()),
            ),
          ),
          _buildCard(
            context,
            'Guard Management',
            Icons.people,
            Colors.orangeAccent,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GuardListScreen()),
            ),
          ),
          _buildCard(
            context,
            'Bulk Attendance',
            Icons.fact_check,
            Colors.purpleAccent,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SupervisorBulkScreen(
                  unitId: 'all',
                  unitName: 'All Units',
                ),
              ),
            ),
          ),
          _buildCard(
            context,
            'Attendance Approvals',
            Icons.approval,
            Colors.redAccent,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AttendanceApprovalScreen(unitId: 'all'),
              ),
            ),
          ),
          _buildCard(
            context,
            'Staff Management',
            Icons.person_add,
            Colors.cyanAccent,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UserManagementScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
