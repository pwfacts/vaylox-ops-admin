import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../../features/guard/guard_app_shell.dart';
import '../../features/supervisor/supervisor_app_shell.dart';
import '../../features/field_officer/field_officer_app_shell.dart';
import '../../features/auth/login_screen.dart';

/// Role-based router that shows completely different apps
class RoleBasedRouter extends StatelessWidget {
  const RoleBasedRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        // Show loading while initializing
        if (!authService.isAuthenticated &&
            authService.state == AuthState.unauthenticated()) {
          return const _LoadingScreen();
        }

        // Not authenticated - show login
        if (!authService.isAuthenticated) {
          return const LoginScreen();
        }

        // Authenticated - route to role-specific app
        switch (authService.userRole) {
          case UserRole.guard:
            return const GuardAppShell();

          case UserRole.supervisor:
            return const SupervisorAppShell();

          case UserRole.fieldOfficer:
          case UserRole.admin:
          case UserRole.superAdmin:
            return const FieldOfficerAppShell();

          default:
            return const _UnknownRoleScreen();
        }
      },
    );
  }
}

/// Loading screen shown during initialization
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text(
              'Loading...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fallback screen for unknown roles
class _UnknownRoleScreen extends StatelessWidget {
  const _UnknownRoleScreen();

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 24),
              const Text(
                'Unknown User Role',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your account role is not recognized. Please contact support.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => authService.logout(),
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
