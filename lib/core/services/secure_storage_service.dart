import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

/// Secure encrypted storage for sensitive data
class SecureStorageService {
  static final SecureStorageService _instance =
      SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // Storage keys
  static const String _keyAuthToken = 'auth_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUserId = 'user_id';
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserRole = 'user_role';
  static const String _keyUserData = 'user_data';
  static const String _keySessionExpiry = 'session_expiry';
  static const String _keyBiometricEnabled = 'biometric_enabled';

  /// Save complete authentication session
  Future<void> saveAuthSession({
    required String authToken,
    required String refreshToken,
    required String userId,
    required String email,
    required String role,
    required Map<String, dynamic> userData,
    DateTime? expiresAt,
  }) async {
    await Future.wait([
      _storage.write(key: _keyAuthToken, value: authToken),
      _storage.write(key: _keyRefreshToken, value: refreshToken),
      _storage.write(key: _keyUserId, value: userId),
      _storage.write(key: _keyUserEmail, value: email),
      _storage.write(key: _keyUserRole, value: role),
      _storage.write(key: _keyUserData, value: jsonEncode(userData)),
      _storage.write(
        key: _keySessionExpiry,
        value: (expiresAt ?? DateTime.now().add(const Duration(days: 30)))
            .toIso8601String(),
      ),
    ]);
  }

  /// Get auth token
  Future<String?> getAuthToken() async {
    return await _storage.read(key: _keyAuthToken);
  }

  /// Get refresh token
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _keyRefreshToken);
  }

  /// Get user ID
  Future<String?> getUserId() async {
    return await _storage.read(key: _keyUserId);
  }

  /// Get user email
  Future<String?> getUserEmail() async {
    return await _storage.read(key: _keyUserEmail);
  }

  /// Get user role
  Future<String?> getUserRole() async {
    return await _storage.read(key: _keyUserRole);
  }

  /// Get full user data
  Future<Map<String, dynamic>?> getUserData() async {
    final data = await _storage.read(key: _keyUserData);
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }

  /// Check if session is valid
  Future<bool> isSessionValid() async {
    final token = await getAuthToken();
    if (token == null) return false;

    final expiryStr = await _storage.read(key: _keySessionExpiry);
    if (expiryStr == null) return false;

    final expiry = DateTime.parse(expiryStr);
    return DateTime.now().isBefore(expiry);
  }

  /// Get session expiry
  Future<DateTime?> getSessionExpiry() async {
    final expiryStr = await _storage.read(key: _keySessionExpiry);
    if (expiryStr == null) return null;
    return DateTime.parse(expiryStr);
  }

  /// Check if biometric is enabled
  Future<bool> isBiometricEnabled() async {
    final value = await _storage.read(key: _keyBiometricEnabled);
    return value == 'true';
  }

  /// Enable/disable biometric authentication
  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(
      key: _keyBiometricEnabled,
      value: enabled.toString(),
    );
  }

  /// Clear all auth data (logout)
  Future<void> clearAuthSession() async {
    await _storage.deleteAll();
  }

  /// Update auth token (after refresh)
  Future<void> updateAuthToken(String token) async {
    await _storage.write(key: _keyAuthToken, value: token);
  }

  /// Get complete stored session
  Future<Map<String, dynamic>?> getStoredSession() async {
    final token = await getAuthToken();
    if (token == null) return null;

    final role = await getUserRole();
    final userId = await getUserId();
    final email = await getUserEmail();
    final userData = await getUserData();
    final refreshToken = await getRefreshToken();

    if (role == null || userId == null) return null;

    return {
      'token': token,
      'refresh_token': refreshToken,
      'user_id': userId,
      'email': email,
      'role': role,
      'user_data': userData,
    };
  }

  /// Generic getString method (for compatibility with other services)
  Future<String?> getString(String key) async {
    return await _storage.read(key: key);
  }

  /// Generic saveString method (for compatibility with other services)
  Future<void> saveString(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  /// Generic deleteKey method (for compatibility with other services)
  Future<void> deleteKey(String key) async {
    await _storage.delete(key: key);
  }
}
