import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/secure_storage_service.dart';

/// User roles in the system
enum UserRole {
  guard,
  supervisor,
  fieldOfficer,
  admin,
  superAdmin;

  static UserRole fromString(String role) {
    switch (role.toLowerCase()) {
      case 'guard':
        return UserRole.guard;
      case 'supervisor':
      case 'field_supervisor':
        return UserRole.supervisor;
      case 'field_officer':
      case 'fieldofficer':
        return UserRole.fieldOfficer;
      case 'admin':
        return UserRole.admin;
      case 'super_admin':
      case 'superadmin':
        return UserRole.superAdmin;
      default:
        throw Exception('Unknown role: $role');
    }
  }

  String get displayName {
    switch (this) {
      case UserRole.guard:
        return 'Guard';
      case UserRole.supervisor:
        return 'Supervisor';
      case UserRole.fieldOfficer:
        return 'Field Officer';
      case UserRole.admin:
        return 'Admin';
      case UserRole.superAdmin:
        return 'Super Admin';
    }
  }
}

/// Authentication state
class AuthState {
  final bool isAuthenticated;
  final UserRole? role;
  final String? userId;
  final String? email;
  final Map<String, dynamic>? userData;

  const AuthState({
    required this.isAuthenticated,
    this.role,
    this.userId,
    this.email,
    this.userData,
  });

  factory AuthState.unauthenticated() {
    return const AuthState(isAuthenticated: false);
  }

  factory AuthState.authenticated({
    required UserRole role,
    required String userId,
    required String email,
    required Map<String, dynamic> userData,
  }) {
    return AuthState(
      isAuthenticated: true,
      role: role,
      userId: userId,
      email: email,
      userData: userData,
    );
  }
}

/// Authentication service with auto-login
class AuthService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SecureStorageService _storage = SecureStorageService();

  AuthState _state = AuthState.unauthenticated();
  AuthState get state => _state;

  bool get isAuthenticated => _state.isAuthenticated;
  UserRole? get userRole => _state.role;
  String? get userId => _state.userId;
  Map<String, dynamic>? get userData => _state.userData;

  /// Initialize auth service and attempt auto-login
  Future<void> initialize() async {
    try {
      // Check if there's a valid stored session
      if (await _storage.isSessionValid()) {
        final session = await _storage.getStoredSession();
        if (session != null) {
          await _restoreSession(session);
          return;
        }
      }

      // Check Supabase session
      final supabaseSession = _supabase.auth.currentSession;
      if (supabaseSession != null) {
        await _loadUserDataAndUpdateState();
      }
    } catch (e) {
      debugPrint('Auto-login failed: $e');
      await _storage.clearAuthSession();
    }
  }

  /// Restore session from encrypted storage
  Future<void> _restoreSession(Map<String, dynamic> session) async {
    try {
      final role = UserRole.fromString(session['role']);

      _state = AuthState.authenticated(
        role: role,
        userId: session['user_id'],
        email: session['email'] ?? '',
        userData: session['user_data'] ?? {},
      );

      notifyListeners();
    } catch (e) {
      debugPrint('Session restoration failed: $e');
      await logout();
    }
  }

  /// Login with email and password
  Future<bool> login({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    try {
      // Authenticate with Supabase
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.session == null) {
        throw Exception('Login failed - no session created');
      }

      // Load user data and determine role
      await _loadUserDataAndUpdateState();

      // Save session if remember me is enabled
      if (rememberMe && _state.isAuthenticated) {
        await _storage.saveAuthSession(
          authToken: response.session!.accessToken,
          refreshToken: response.session!.refreshToken ?? '',
          userId: _state.userId!,
          email: email,
          role: _state.role!.name,
          userData: _state.userData ?? {},
        );
      }

      return true;
    } catch (e) {
      debugPrint('Login error: $e');
      return false;
    }
  }

  /// Load user data and update auth state
  Future<void> _loadUserDataAndUpdateState() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      _state = AuthState.unauthenticated();
      notifyListeners();
      return;
    }

    try {
      // Try to get guard data first
      final guardResponse = await _supabase
          .from('guards')
          .select('*, organization_id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (guardResponse != null) {
        _state = AuthState.authenticated(
          role: UserRole.guard,
          userId: user.id,
          email: user.email ?? '',
          userData: {
            ...guardResponse,
            'guard_id': guardResponse['id'],
          },
        );
        notifyListeners();
        return;
      }

      // Check organization_users table for other roles
      final orgUserResponse = await _supabase
          .from('organization_users')
          .select('role, organization_id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (orgUserResponse != null) {
        final roleStr = orgUserResponse['role'] as String;
        UserRole role;

        // Map database roles to app roles
        if (roleStr == 'admin' || roleStr == 'super_admin') {
          role =
              roleStr == 'super_admin' ? UserRole.superAdmin : UserRole.admin;
        } else if (roleStr == 'field_officer') {
          // Check if they have supervisor privileges
          final supervisorUnits = await _supabase
              .from('field_officer_units')
              .select('unit_id')
              .eq('user_id', user.id);

          // If they manage only one unit, they're a supervisor
          role = supervisorUnits.length == 1
              ? UserRole.supervisor
              : UserRole.fieldOfficer;
        } else {
          role = UserRole.fieldOfficer;
        }

        _state = AuthState.authenticated(
          role: role,
          userId: user.id,
          email: user.email ?? '',
          userData: {
            ...orgUserResponse,
            'organization_id': orgUserResponse['organization_id'],
          },
        );
        notifyListeners();
        return;
      }

      throw Exception('User not found in any role table');
    } catch (e) {
      debugPrint('Error loading user data: $e');
      _state = AuthState.unauthenticated();
      notifyListeners();
      rethrow;
    }
  }

  /// Logout and clear session
  Future<void> logout() async {
    await _supabase.auth.signOut();
    await _storage.clearAuthSession();
    _state = AuthState.unauthenticated();
    notifyListeners();
  }

  /// Refresh session
  Future<void> refreshSession() async {
    try {
      final refreshToken = await _storage.getRefreshToken();
      if (refreshToken == null) {
        throw Exception('No refresh token available');
      }

      final response = await _supabase.auth.refreshSession();
      if (response.session != null) {
        await _storage.updateAuthToken(response.session!.accessToken);
      }
    } catch (e) {
      debugPrint('Session refresh failed: $e');
      await logout();
    }
  }

  /// Change password
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      // Re-authenticate with current password first
      final email = _state.email;
      if (email == null) return false;

      await _supabase.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );

      // Update password
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      return true;
    } catch (e) {
      debugPrint('Password change failed: $e');
      return false;
    }
  }

  /// Request password reset
  Future<bool> requestPasswordReset(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
      return true;
    } catch (e) {
      debugPrint('Password reset request failed: $e');
      return false;
    }
  }
}
