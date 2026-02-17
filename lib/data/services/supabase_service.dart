import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import '../../core/constants/app_constants.dart';

final _logger = Logger();

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  // Use a getter to access the client, ensuring it's always the current instance
  // This avoids LateInitializationError when initialization happens externally (e.g. main_web.dart)
  static SupabaseClient get client => Supabase.instance.client;

  Future<void> initialize() async {
    // This method is kept for compatibility but initialization is primarily handled by main.dart/main_web.dart
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
    } catch (e) {
      _logger.e('Supabase initialization failed: $e');
      rethrow;
    }
  }

  // Auth helper methods
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    return await client.auth.signUp(
      email: email,
      password: password,
      data: data,
    );
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  Session? get currentSession => client.auth.currentSession;
  User? get currentUser => client.auth.currentUser;
}
