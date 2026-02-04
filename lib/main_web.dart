import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data/services/supabase_service.dart';
import 'presentation/screens/admin_dashboard_screen.dart';
import 'presentation/screens/payroll_wizard_screen.dart';
import 'presentation/screens/guard_list_screen.dart';
import 'presentation/screens/supervisor_bulk_screen.dart';
import 'presentation/screens/attendance_approval_screen.dart';
import 'presentation/screens/user_management_screen.dart';

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
      // Add timeout to prevent infinite hanging
      await Future.any([
        _doInitialization(),
        Future.delayed(const Duration(seconds: 10), () {
          throw TimeoutException('Initialization timed out after 10 seconds');
        })
      ]);
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _doInitialization() async {
    try {
      final supabaseService = SupabaseService();
      await supabaseService.initialize();
    } catch (e) {
      // If Supabase fails, try to initialize manually
      print('Primary initialization failed: $e');
      try {
        await Supabase.initialize(
          url: 'https://fcpbexqyyzdvbiwplmjt.supabase.co',
          anonKey: 'YOUR_FALLBACK_KEY_HERE',
          authOptions: const FlutterAuthClientOptions(
            authFlowType: AuthFlowType.implicit,
          ),
        );
      } catch (fallbackError) {
        print('Fallback initialization also failed: $fallbackError');
        rethrow;
      }
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
              TextButton(
                onPressed: () {
                  // Skip initialization and go directly to login
                  setState(() {
                    _isInitialized = true;
                    _hasError = false;
                  });
                },
                child: const Text('Skip & Continue'),
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
          return const WebAdminHome();
        }
        return const WebLoginScreen();
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

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Login failed: $e')));
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
