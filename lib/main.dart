import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/app_constants.dart';
import 'data/services/supabase_service.dart';
import 'presentation/screens/guard_list_screen.dart';
import 'presentation/screens/attendance_screen.dart';
import 'presentation/screens/supervisor_bulk_screen.dart';
import 'presentation/screens/attendance_approval_screen.dart';
import 'presentation/screens/payroll_wizard_screen.dart';
import 'presentation/screens/admin_dashboard_screen.dart';
import 'core/theme/app_colors.dart';

import 'data/services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final supabaseService = SupabaseService();
  await supabaseService.initialize();

  // Start Offline Sync Service
  SyncService().start();

  runApp(
    const ProviderScope(
      child: VayloxOpsApp(),
    ),
  );
}

class VayloxOpsApp extends StatelessWidget {
  const VayloxOpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vaylox Ops',
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
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final session = snapshot.data?.session;
        if (session != null) {
          return const MainShell();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const AttendanceScreen(),
    const GuardListScreen(),
    const SupervisorDashboard(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'Attendance'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Guards'),
          NavigationDestination(icon: Icon(Icons.dashboard_customize), label: 'Supervisor'),
        ],
      ),
    );
  }
}

class SupervisorDashboard extends StatelessWidget {
  const SupervisorDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    const String demoUnitId = 'placeholder_unit_id';
    const String demoUnitName = 'Main Unit (BH01)';

    return Scaffold(
      appBar: AppBar(title: const Text('Supervisor Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildActionCard(
            context,
            title: 'Executive Analytics',
            subtitle: 'Overview of company performance',
            icon: Icons.analytics,
            color: Colors.blueAccent,
            onTap: () => Navigator.push(
              context, 
              MaterialPageRoute(builder: (context) => const AdminDashboardScreen())
            ),
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            context,
            title: 'Bulk Attendance',
            subtitle: 'Mark attendance for multiple guards',
            icon: Icons.group_add,
            onTap: () => Navigator.push(
              context, 
              MaterialPageRoute(builder: (context) => const SupervisorBulkScreen(
                unitId: demoUnitId,
                unitName: demoUnitName,
              ))
            ),
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            context,
            title: 'Verify Fallbacks',
            subtitle: 'Review manual attendance requests',
            icon: Icons.verified_user,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AttendanceApprovalScreen(
                unitId: demoUnitId,
              ))
            ),
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            context,
            title: 'Monthly Payroll',
            subtitle: 'Calculate and generate salary slips',
            icon: Icons.account_balance_wallet,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PayrollWizardScreen(
                unitId: demoUnitId,
                unitName: demoUnitName,
              ))
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.blueAccent,
  }) {
    return Card(
      elevation: 0,
       color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(20),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 28, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[400])),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: Main_AxisAlignment.center,
          children: [
            const Text(
              'JDS MANAGEMENT',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20)),
              child: const Text('Login Default Account'),
            ),
          ],
        ),
      ),
    );
  }
}
