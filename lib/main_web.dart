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
    // Debug log environment variables
    const envUrl = String.fromEnvironment('VITE_SUPABASE_URL');
    const envKey = String.fromEnvironment('VITE_SUPABASE_ANON_KEY');
    
    print('Environment URL: $envUrl');
    print('Environment Key: ${envKey.isNotEmpty ? 'PRESENT' : 'MISSING'}');
    
    // For now, skip Supabase initialization to test if app loads
    try {
      if (envUrl.isNotEmpty && envKey.isNotEmpty) {
        await Supabase.initialize(
          url: envUrl,
          anonKey: envKey,
          authOptions: const FlutterAuthClientOptions(
            authFlowType: AuthFlowType.implicit,
          ),
        );
        print('Supabase initialized successfully');
      } else {
        print('Skipping Supabase - using fallback credentials');
        await Supabase.initialize(
          url: 'https://fcpbexqyyzdvbiwplmjt.supabase.co',
          anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjcGJleHF5eXpkdmJpd3BsbWp0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk2NjU2OTYsImV4cCI6MjA4NTI0MTY5Nn0.4PQByF7K7H0kTGgYxchdVJgqy-5pzGTC_FqGJQ50muw',
          authOptions: const FlutterAuthClientOptions(
            authFlowType: AuthFlowType.implicit,
          ),
        );
      }
    } catch (e) {
      print('Supabase initialization failed, continuing without it: $e');
      // Continue without Supabase for now
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
  bool _isSignup = false;

  Future<void> _signup() async {
    setState(() => _isLoading = true);
    try {
      print('Attempting signup with email: ${_emailController.text.trim()}');
      final response = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      print('Signup response: ${response.session != null ? 'Success' : 'Check email'}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.session != null 
                ? 'Account created successfully!'
                : 'Check your email for verification link'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Signup error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Signup failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _bypassLogin() {
    // Temporary bypass for testing
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const WebAdminHome()),
    );
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      print('Attempting login with email: ${_emailController.text.trim()}');
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      print('Login response: ${response.session != null ? 'Success' : 'Failed'}');
    } catch (e) {
      print('Login error details: $e');
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
                        onPressed: _isLoading ? null : (_isSignup ? _signup : _login),
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
                            : Text(
                                _isSignup ? 'Create Account' : 'Sign In',
                                style: const TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isSignup = !_isSignup;
                            });
                          },
                          child: Text(
                            _isSignup 
                                ? 'Already have account? Sign In' 
                                : 'Need an account? Sign Up',
                            style: const TextStyle(color: Colors.blueAccent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _bypassLogin,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.orange.withOpacity(0.2),
                        padding: const EdgeInsets.all(12),
                      ),
                      child: const Text(
                        '🚀 Skip Login (Demo Mode)',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Test Credentials:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Email: admin@vaylox.com',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: Colors.white70,
                            ),
                          ),
                          Text(
                            'Password: admin123',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: Colors.white70,
                            ),
                          ),
                        ],
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
